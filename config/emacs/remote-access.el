;;; remote-access.el --- Shared remote access configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;; The client and server come from the same locked Nix input. Home Manager
;; supplies the load paths, including the newer TRAMP required by TRAMP-RPC.
(require 'tramp-rpc)

;; RPC hosts use the Home Manager server on their SSH shell's PATH. Our fish
;; shellInit adds the Nix profile even for noninteractive SSH commands. Do not
;; download a second server outside Nix; unmanaged hosts can still use /ssh:.
;; These must be global: upstream reads them before applying host profiles.
(setq tramp-rpc-deploy-never-deploy t
      tramp-rpc-deploy-remote-binary-path nil)

;; /-:jay@tungo.org:/path defaults to RPC; explicit /ssh: paths stay unchanged.
;; C-x C-f /rpc:jay@tungo.org:/home/jay/ opens the remote home directory.
(add-to-list 'tramp-default-method-alist '("\\`tungo\\.org\\'" nil "rpc"))

;;; remote-access.el ends here
