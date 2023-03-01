(define-module (my-project services messaging)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (ice-9 match)
  #:use-module (ice-9 format)
  #:autoload   (gnu build linux-container) (%namespaces)
  #:use-module ((gnu system file-systems) #:select (file-system-mapping))
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services configuration)
  #:use-module (gnu system shadow)
  #:use-module (gnu packages admin)
  #:use-module (guix modules)
  #:use-module (guix records)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (gnu packages messaging)


  #:export (mosquitto-service-type
	    mosquitto-configuration
	    mosquitto-listener-configuration))

(define (uglify-field-name field-name)
  (let ((str (symbol->string field-name)))
    (string-join (string-split (if (string-suffix? "?" str)
				   (substring str 0 (1- (string-length str)))
				   str)
			       #\-)
		 "_")))

(define (serialize-field field val)
  (format #f "~a ~a~&" (uglify-field-name field) val))

(define serialize-string serialize-field)

(define (serialize-maybe-string field val)
  (if val
      (serialize-string field val)
      (string-append "# " (serialize-string field ""))))

(define (maybe-string? x)
  (or (nil? x)
      (string? x)))

(define serialize-integer serialize-field)

(define (serialize-list field val)
  (serialize-field field
		   (format #f "~{~a~^ ~}" val)))

(define (serialize-boolean field val)
  (serialize-field field (if val "true" "false")))

(define (serialize-listener val)
  (serialize-configuration val mosquitto-listener-configuration-fields))

(define (serialize-listener-list field val)
  (apply string-append (map serialize-listener val)))

(define listener-list? pair?)

(define-configuration mosquitto-listener-configuration
  ;; this has to come first it marks a new listener when serialized.
  (listener
   (list '(1883))
   "Tuple '(port &optional bind-address) only port is required.
Listen for incoming network connection on the specified port. A
second optional argument allows the listener to be bound to a specific
ip address/hostname. If this variable is used and neither the global
bind_address nor port options are used then the default listener will
not be started.
The bind address/host option allows this listener to be
bound to a specific IP address by passing an IP address or
hostname. For websockets listeners, it is only possible to pass an IP
address here.

This option may be specified multiple times. See also the
mount-point option.")
  (bind-interface
   (maybe-string #f)
   " Bind the listener to a specific interface. This is similar to
 the [ip address/host name] part of the listener definition, but is useful
 when an interface has multiple addresses or the address may change. It is
 valid to use this with the [ip address/host name] part of the listener
 definition, but take care that the interface you are binding to contains the
 address you are binding to, otherwise you will not be able to connect.
 Only available on Linux and requires elevated privileges.")
  (http-dir
   (maybe-string #f)
   "When a listener is using the websockets protocol, it is possible
to serve http data as well. Set http_dir to a directory which contains
the files you wish to serve. If this option is not specified, then no
normal http connections will be possible.")
  (max-connections
   (integer -1)
   "Limit the total number of clients connected for the
	    current listener. Set to -1 to have \"unlimited\"
	    connections. Note that other limits may be imposed that
	    are outside the control of mosquitto."))

(define-configuration mosquitto-configuration
  (mosquitto
   (file-like mosquitto)
   "The mosquitto package.")
  (pid-file
   (string "/var/run/mosquitto/mosquitto.pid")
   "PID file")
  (allow-anonymous?
   (boolean #t)
   "Allow clients to connect without providing a user name.")
  (allow-duplicate-messages?
   (boolean #t)
   "If a client is subscribed to multiple subscriptions that
ove`rlap, e.g. foo/# and foo/+/baz , then MQTT expects that when the
broker receives a message on a topic that matches both subscriptions,
such as foo/bar/baz, then the client should only receive the message
once.")
  (allow-zero-length-clientid?
   (boolean #t)
   "MQTT 3.1.1 and MQTT 5 allow clients to connect with a zero length
client id and have the broker generate a client id for them. Use this
option to allow/disallow this behaviour.")
  (bind-address
   (maybe-string #f)
   "Listen for incoming network connections on the specified IP
address/hostname only. This is useful to restrict access to certain
network interfaces. To restrict access to mosquitto to the local host
only, use \"bind_address localhost\".  This only applies to the
default listener.  Use the listener option to control other listeners.")
  (extra-listeners
   (listener-list (list (mosquitto-listener-configuration)))
   "A list of mosquitto-listener"))

(define (mosquitto-conf config)
  (computed-file "mosquitto.conf"
		 #~(call-with-output-file #$output
		     (lambda (port)
		       (format port #$(serialize-configuration
				       config (filter-configuration-fields
					       mosquitto-configuration-fields
					       '(mosquitto
						 extra-listeners)
					       #t)))
		       (format port "~a" (string-append "\n"
							#$@(map (cut serialize-configuration <>
								     mosquitto-listener-configuration-fields)
								(mosquitto-configuration-extra-listeners config))))))))

(define (mosquitto-shepherd-service config)
  (let* ((mosquitto
	  (mosquitto-configuration-mosquitto config))
	 (conf (mosquitto-conf config))
	 (mosquitto* (file-append mosquitto "/sbin/mosquitto")))

    (with-imported-modules (source-module-closure
			    '((gnu build shepherd)
			      (gnu system file-systems)))
      (list (shepherd-service
	     (provision '(mosquitto mqtt-broker))
	     (requirement '(user-processes networking))
	     (modules '((gnu build shepherd)))
	     (start #~(make-forkexec-constructor
		       (list #$mosquitto* "-c" #$conf)
		       #:user "mosquitto" #:group "mosquitto"
		       #:log-file "/var/log/mosquitto.log"
		       #:environment-variables
		       (list "SSL_CERT_DIR=/run/current-system/profile/etc/ssl/certs"
			     "SSL_CERT_FILE=/run/current-system/profile/etc/ssl/certs/ca-certificates.crt")))
	     (stop #~(make-kill-destructor #:grace-period 30)))))))

(define %mosquitto-accounts
  (list (user-group (name "mosquitto") (system? #t))
	(user-account
	 (name "mosquitto")
	 (group "mosquitto")
	 (system? #t)
	 (comment "mosquitto daemon user")
	 (home-directory "/var/empty")
	 (shell (file-append shadow "/sbin/nologin")))))

(define %mosquitto-activation
  #~(begin
      (use-modules (guix build utils))

      (mkdir-p "/var/run/mosquitto")
      (let ((user (getpwnam "mosquitto")))
	(chown "/var/run/mosquitto"
	       (passwd:uid user) (passwd:gid user)))))

(define mosquitto-service-type
  (service-type (name 'mosquitto)
		(extensions
		 (list (service-extension shepherd-root-service-type
					  mosquitto-shepherd-service)
		       (service-extension activation-service-type
					  (const %mosquitto-activation))
		       (service-extension account-service-type
					  (const %mosquitto-accounts))))
		(default-value (mosquitto-configuration))
		(description
		 "Run Mosquitto MQTT broker.")))
