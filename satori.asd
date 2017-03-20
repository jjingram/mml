(asdf:defsystem #:satori
  :description "Yet another Lisp on LLVM"
  :author "Jarrod Jeffrey Ingram <jarrod.jeffi@gmail.com>"
  :license "BSD-3-Clause"
  :depends-on (#:alexandria #:llvm)
  :serial t
  :pathname "src/"
  :components ((:file "package")
               (:file "satori")
               (:file "util")
               (:file "eval")
               (:file "closure")
               (:file "compile")
               (:file "type")
               (:file "substitute")))

(asdf:defsystem #:satori-test
  :description "Test suite for Satori"
  :depends-on (#:satori #:prove)
  :serial t
  :pathname "t/"
  :components ((:file "package")
               (:file "expression")
               (:file "definition")))
