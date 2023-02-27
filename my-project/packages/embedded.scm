(define-module (my-project packages embedded)
  #:use-module ((guix licenses) :prefix license:)
  #:use-module (guix packages)
  #:use-module (zephyr build-system zephyr)
  #:use-module (zephyr packages zephyr)
  #:use-module (zephyr packages zephyr-xyz)
  #:use-module (my-project))

(define-public k64f-temp-firmware-stand-alone
  (let ((commit "a4bc0cd5213af7448d690fe873633ec4f7c86f51"))
    (package
      (name "k64f-temp-firmware")
      (version (git-version "0.0" "0" commit))
      (home-page %project-home-page)
      (source (origin (method (git-fetch))
		      (uri (git-reference
			    (url "https://github.com/paperclip4465/k64f-temp-firmware")
			    (commit commit)))
		      (file-name (git-file-name name version))
		      (sha256
		       (base32 "120gwwxrc1sszm0wzxdyla5q29q1cprsxxr73xx027kxgbb6m3mw"))))
      (build-system zephyr-build-system)
      (outputs '("out" "debug"))
      (inputs (list hal-nxp
		    hal-cmsis
		    zcbor
		    zephyr-mcuboot))
      (arguments
       `(#:zephyr zephyr-3.1
	 #:configure-flags '("-DBOARD=frdm_k64f")))
      (synopsis "Temperature measurement firmware for k64f")
      (description "This firmware measures the temperature every 60 seconds
and publishes it over MQTT. In addition it also implements an SMP server over
UDP that can be used for firmware update/device controll.")
      (license license:gpl3+))))

(define-public k64f-temp-firmware
  (let ((base k64f-temp-firmware-stand-alone))
    (package (inherit base)
      (arguments
       (substitute-keyword-arguments base
	 ((#:configure-flags flags)
	  `(append '("-DCONFIG_BOOTLOADER_MCUBOOT=y")
		   ,flags))))
      (description
       (string-append (package-description base)
		      "This firmware is linked against the primary
image slot and must be loaded by mcuboot. (see device tree)")))))
