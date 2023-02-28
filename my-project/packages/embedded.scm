(define-module (my-project packages embedded)
  #:use-module ((guix licenses) :prefix license:)
  #:use-module (guix gexp)
  #:use-module (guix utils)
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
  (let ((commit "b32844ee722375c042cdd9a5f6b70c6716979f79"))
    (package
      (name "k64f-temp-firmware-stand-alone")
      (version (git-version "0.0" "0" commit))
      (home-page %project-home-page)
      (source (origin (method git-fetch)
		      (uri (git-reference
			    (url "https://github.com/paperclip4465/k64f-temp-firmware")
			    (commit commit)))
		      (file-name (git-file-name name version))
		      (sha256
		       (base32 "1g5q8yzsrrsbd6z4h9hnspccrgswcr4d31y0r2sz2hns53lz8kp4"))))
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


(define-public k64f-bootloader
  (let ((mcuboot (make-mcuboot "frdm_k64f"
			       ;; Use special dev key instead of production
			       (local-file "../../dev.pem")
			       #:extra-zephyr-modules (list hal-cmsis hal-nxp)
			       #:extra-configure-flags
			       '(;; k64 doesn't have fancy crypto hardware
				 ;; so we cannot use RSA keys.
				 "-DCONFIG_BOOT_SIGNATURE_TYPE_ECDSA_P256=y"
				 "-DCONFIG_BOOT_SIGNATURE_TYPE_RSA=n"
				 "-DCONFIG_BOOT_ECDSA_TINYCRYPT=y"))))
    (package (inherit mcuboot)
	     (name "k64f-bootloader"))))
