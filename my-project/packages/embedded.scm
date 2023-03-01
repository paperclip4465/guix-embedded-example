(define-module (my-project packages embedded)
  #:use-module ((guix licenses) :prefix license:)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix build utils)
  #:use-module (guix packages)
  #:use-module (guix git-download)
  #:use-module (zephyr build-system zephyr)
  #:use-module (zephyr packages zephyr)
  #:use-module (zephyr packages zephyr-xyz)
  #:use-module (ice-9 format)
  #:use-module (my-project))

(define %firmware-signing-key
  (local-file "../../dev.pem"))

(define-public k64f-temp-firmware-stand-alone
  (let ((commit "v0.0.1"))
    (package
      (name "k64f-temp-firmware-stand-alone")
      (version "0.0.1")
      (home-page %project-home-page)
      (source (origin (method git-fetch)
		      (uri (git-reference
			    (url "https://github.com/paperclip4465/k64f-temp-firmware")
			    (commit commit)))
		      (file-name (git-file-name name version))
		      (sha256
		       (base32 "1ysmbazgj8jbnz1jbb6n8l4srs1jnjj7r9lsvhwzjxaqygikal84"))))
      (build-system zephyr-build-system)
      (outputs '("out" "debug"))
      (inputs (list hal-nxp
		    hal-cmsis
		    zcbor
		    zephyr-mcuboot))
      (arguments
       `(#:zephyr ,zephyr-3.1
	 #:bin-name "k64f-temp"
	 #:board "frdm_k64f"))
      (synopsis "Temperature measurement firmware for k64f")
      (description "This firmware measures the temperature every 60 seconds
and publishes it over MQTT. In addition it also implements an SMP server over
UDP that can be used for firmware update/device control.")
      (license license:gpl3+))))

(define* (signed-firmware firmware #:optional confirmed?)
  "Adds a signing phases to FIRMWARE."
  (package
    (inherit firmware)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
	 ;; Replace output binary with signed version.
	 (add-before 'install 'sign-firmware
	   (lambda* (#:key inputs #:allow-other-keys)
	     (let ((bin "zephyr/zephyr.bin")
		   (unsigned "zephyr/zephyr.unsigned.bin")
		   (key (assoc-ref inputs "signing-key")))
	       (copy-file bin unsigned)

	       (let ((imgtool-args `("imgtool" "sign"
				     "--key" ,key
				     "--align" "4"
				     "--header-size" "0x200"
				     "--slot-size" "0x60000"
				     "--version" ,,(package-version firmware)
				     "--pad"
				     ,@(if ,confirmed? (list "--confirm") '())
				     ,unsigned ,bin)))
		 (format #t "~{~a~^ ~}~&" imgtool-args)
		 (apply system* imgtool-args))))))
       ,@(package-arguments firmware)))
    (native-inputs
     (append `(("signing-key" ,%firmware-signing-key)
	       ("imgtool" ,imgtool))
	     (package-native-inputs firmware)))
    (description (string-append "Signed firmware suitable for MCUBOOT\n\n"
				(package-description firmware)))))

(define-public k64f-temp-firmware
  (let ((base k64f-temp-firmware-stand-alone))
    (package
      (inherit base)
      (name "k64f-temp-firmware")
      (arguments
       `(#:configure-flags '("-DCONFIG_BOOTLOADER_MCUBOOT=y"
			     "-DCONFIG_ROM_START_OFFSET=0x200")
	 ,@(package-arguments base))))))

(define-public k64f-temp-firmware-signed
  (let ((base (signed-firmware k64f-temp-firmware %firmware-signing-key)))
    (package
      (inherit base)
      (name "k64f-temp-firmware-signed"))))

(define-public k64f-bootloader
  (let ((mcuboot (make-mcuboot "frdm_k64f" %firmware-signing-key
			       #:extra-zephyr-modules (list hal-cmsis hal-nxp)
			       #:extra-configure-flags
			       '( ;; k64 doesn't have fancy crypto hardware
				 ;; so we cannot use RSA keys.
				 "-DCONFIG_BOOT_SIGNATURE_TYPE_ECDSA_P256=y"
				 "-DCONFIG_BOOT_SIGNATURE_TYPE_RSA=n"
				 "-DCONFIG_BOOT_ECDSA_TINYCRYPT=y"))))
    (package (inherit mcuboot)
      (name "k64f-bootloader"))))
