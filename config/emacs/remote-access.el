;;; remote-access.el --- Shared remote access configuration -*- lexical-binding: t; -*-

;; The client and server come from the same locked Nix input. Home Manager
;; supplies the load paths, including the newer TRAMP required by TRAMP-RPC.
(require 'tramp-rpc)

;; Only this managed host bypasses upstream's automatic binary deployment.
;; Use an absolute remote path: GUI/SSH shells need not inherit the Nix PATH.
(connection-local-set-profile-variables
 'jb-tramp-rpc-tungo
 '((tramp-rpc-deploy-never-deploy . t)
   (tramp-rpc-deploy-remote-binary-path . "/home/jay/.nix-profile/bin/tramp-rpc-server")))
(connection-local-set-profiles
 '(:application tramp :protocol "rpc" :machine "tungo.org")
 'jb-tramp-rpc-tungo)

;; /jay@tungo.org:/path defaults to RPC; explicit /ssh: paths stay unchanged.
;; C-x C-f /rpc:jay@tungo.org:/home/jay/ opens the remote home directory.
(add-to-list 'tramp-default-method-alist '("\\`tungo\\.org\\'" nil "rpc"))

;;; remote-access.el ends here
