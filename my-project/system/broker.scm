(define-module (my-project system broker)
  #:use-module (srfi srfi-1)
  #:use-module (gnu)
  #:use-module (gnu packages screen)
  #:use-module (gnu packages ssh)
  #:use-module (gnu services networking)
  #:use-module (gnu services ssh)
  #:use-module (my-project services messaging))

(use-service-modules desktop mcron networking spice ssh xorg sddm web)
(use-package-modules bootloaders certs fonts nvi
		     package-management wget xorg)

(define vm-image-motd (plain-file "motd" "
\x1b[1;37mThis is the GNU system.  Welcome!\x1b[0m

This instance of Guix is a template for virtualized environments.
You can reconfigure the whole system by adjusting /etc/config.scm
and running:

  guix system reconfigure /etc/config.scm

Run '\x1b[1;37minfo guix\x1b[0m' to browse documentation.

\x1b[1;33mConsider setting a password for the 'root' and 'guest' \
accounts.\x1b[0m
"))

(operating-system
  (host-name "mqtt-broker-1")
  (locale "en_US.utf8")
  ;; Boot in "legacy" BIOS mode, assuming /dev/sdX is the
  ;; target hard disk, and "my-root" is the label of the target
  ;; root file system.
  (bootloader (bootloader-configuration
	       (bootloader grub-bootloader)
	       (targets '("/dev/vda"))
	       (terminal-outputs '(console))))

  (file-systems (cons (file-system
			(mount-point "/")
			(device "/dev/vda1")
			(type "ext4"))
		      %base-file-systems))
  (services
   (append (list (service openssh-service-type)
		 (service dhcp-client-service-type)
		 (service mosquitto-service-type))

	   ;; Remove some services that don't make sense in a VM.
	   (remove (lambda (service)
		     (let ((type (service-kind service)))
		       (or (memq type
				 (list gdm-service-type
				       sddm-service-type
				       wpa-supplicant-service-type
				       cups-pk-helper-service-type
				       network-manager-service-type
				       modem-manager-service-type))
			   (eq? 'network-manager-applet
				(service-type-name type)))))
		   (modify-services %desktop-services
		     (login-service-type config =>
					 (login-configuration
					  (inherit config)
					  (motd vm-image-motd))))))))
