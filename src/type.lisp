;; See: http://www.cis.upenn.edu/~bcpierce/tapl/checkers/fullrecon/core.ml

(in-package #:satori)

(defun recon (x ctx defs)
  (cond
    ((null x) `(nil nil nil))
    ((integerp x) `(i32 nil (i32 ,x)))
    ((symbolp x) (cond
                   ((assoc x ctx)
                    (let* ((type (second (assoc x ctx))))
                      `(,type nil (variable ,x ,type))))
                   (t (error 'unknown-variable-name :argument x))))
    ((case (first x)
       (lambda (let ((params `(,(gensym) . ,(second x)))
                     (body (rest (rest x))))
                 (let* ((param-syms (alexandria:make-gensym-list (length params) "T"))
                        (param-types (map 'list
                                          #'list
                                          (make-list (length param-syms)
                                                     :initial-element 'type-variable)
                                          param-syms))
                        (callee `(%callee (lambda ,param-types
                                            (type-variable ,(gensym "T")))))
                        (ctx* (append (map 'list #'list params param-types) ctx))
                        (ctx** (or (and (find-anywhere '%callee body)
                                        `(,callee . ,ctx*))
                                   ctx*))
                        (body-recon (map 'list
                                         #'(lambda (x)
                                             (recon x ctx** defs))
                                         body))
                        (body-last (first (last body-recon)))
                        (body-type (first body-last))
                        (body-constr (second body-last))
                        (params* (map 'list
                                      #'(lambda (param type)
                                          `(variable ,param ,type))
                                      params
                                      param-types))
                        (body* (map 'list #'third body-recon))
                        (free-vars (free x))
                        (lam `(lambda ,param-types ,body-type))
                        (new-constr `((,lam ,(second callee))))
                        (constr (append new-constr body-constr)))
                   `(,lam
                     ((,(first param-types)
                       (structure
                        ,@(map 'list
                               #'(lambda (fv)
                                   (second (assoc fv ctx*)))
                               (set-difference free-vars defs))))
                      . ,constr)
                     (lambda% ,params* ,body-type ,@body*)))))
       (let (let* ((vars (map 'list #'first (second x)))
                   (exps (map 'list #'second (second x)))
                   (exps*
                     (map 'list
                          #'(lambda (var exp)
                              (substitute* `((,var . %callee)) exp))
                          vars exps))
                   (body (rest (rest x)))
                   (sub (map 'list
                             #'(lambda (var exp)
                                 (when (isval exp)
                                   `(,var . ,exp)))
                             vars
                             exps*))
                   (exps** (map 'list #'(lambda (x) (substitute* sub x)) exps*))
                   (body* (substitute* sub body))
                   (binding-constr '())
                   (annotated-bindings '())
                   (ctx1 (reverse
                          (reduce
                           #'(lambda (binding ctx)
                               (let* ((var (first binding))
                                      (exp (second binding))
                                      (recon1 (recon exp ctx defs))
                                      (exp-type (first recon1))
                                      (constr1 (second recon1))
                                      (exp* (third recon1)))
                                 (if (not (isval exp*))
                                     (progn
                                       (setf annotated-bindings
                                             `(((variable ,var ,exp-type) ,exp*)
                                               . ,annotated-bindings))
                                       (setf binding-constr `(,constr1 . ,binding-constr))
                                       `((,var ,exp-type) . ,ctx))
                                     ctx)))
                           (map 'list #'list vars exps**)
                           :initial-value ctx
                           :from-end t)))
                   (annotated-bindings* (reverse annotated-bindings))
                   (ctx* (remove nil ctx1))
                   (recon2 (map 'list #'(lambda (x) (recon x ctx* defs)) body*))
                   (body-last (first (last recon2)))
                   (body-type (first body-last))
                   (body-constr (second body-last))
                   (annotated-body (map 'list #'third recon2)))
              `(,body-type
                ,(append (first binding-constr) body-constr)
                (let% ,annotated-bindings* ,body-type ,@annotated-body))))
       (define (let* ((name (second x))
                      (rec (recursive-definition-p x))
                      (param-syms (alexandria:make-gensym-list (length rec) "T"))
                      (param-types (map 'list #'list
                                        (make-list (length rec)
                                                   :initial-element 'type-variable)
                                        param-syms))
                      (retty `(type-variable ,(gensym "T")))
                      (ctx* (or (and rec `((,name (lambda ,param-types ,retty)) . ,ctx))
                                ctx))
                      (exp-recon (recon (third x) ctx* `(,name . ,defs)))
                      (exp-type (first exp-recon))
                      (exp-constr (second exp-recon))
                      (exp* (third exp-recon)))
                 `(,exp-type
                   ,exp-constr
                   (define% (variable ,name ,exp-type) ,exp*))))
       (if (let* ((pred (second x))
                  (true (third x))
                  (false (fourth x))
                  (pred-recon (recon pred ctx defs))
                  (pred-type (first pred-recon))
                  (pred-constr (second pred-recon))
                  (pred-exp (third pred-recon))
                  (true-recon (recon true ctx defs))
                  (true-type (first true-recon))
                  (true-constr (second true-recon))
                  (true-exp (third true-recon))
                  (false-recon (recon false ctx defs))
                  (false-type (first false-recon))
                  (false-constr (second false-recon))
                  (false-exp (third false-recon))
                  (new-constr `((,pred-type i1)))
                  (constr (append new-constr pred-constr true-constr false-constr))
                  (rettype (or (and (not (equal true-type false-type))
                                    `(union ,true-type ,false-type))
                               true-type)))
             `(,rettype ,constr (if% ,pred-exp ,pred-type ,rettype ,true-exp ,false-exp))))
       (eq (let* ((lhs (second x))
                  (lhs-recon (recon lhs ctx defs))
                  (lhs-type (first lhs-recon))
                  (lhs-constr (second lhs-recon))
                  (lhs-exp (third lhs-recon))
                  (rhs (third x))
                  (rhs-recon (recon rhs ctx defs))
                  (rhs-type (first rhs-recon))
                  (rhs-constr (second rhs-recon))
                  (rhs-exp (third rhs-recon))
                  (new-constr `((,lhs-type ,rhs-type)))
                  (constr (append new-constr lhs-constr rhs-constr)))
             `(i1 ,constr (eq% ,lhs-type ,lhs-exp ,rhs-exp))))
       ((add sub mul sdiv srem)
        (let* ((lhs (second x))
               (lhs-recon (recon lhs ctx defs))
               (lhs-type (first lhs-recon))
               (lhs-constr (second lhs-recon))
               (lhs-exp (third lhs-recon))
               (rhs (third x))
               (rhs-recon (recon rhs ctx defs))
               (rhs-type (first rhs-recon))
               (rhs-constr (second rhs-recon))
               (rhs-exp (third rhs-recon))
               (new-constr `((,lhs-type i32) (,rhs-type i32) (,lhs-type ,rhs-type)))
               (constr (append new-constr lhs-constr rhs-constr))
               (new-op (intern (concatenate 'string (string (first x)) "%"))))
          `(i32 ,constr (,new-op ,lhs-exp ,rhs-exp))))
       (cons (let* ((elements (rest x))
                    (element-recons (map 'list
                                         #'(lambda (x)
                                             (recon x ctx defs))
                                         elements))
                    (element-types (map 'list #'first element-recons))
                    (element-constrs (mappend #'second element-recons))
                    (element-exps (map 'list #'third element-recons)))
               `((structure ,@element-types)
                 ,element-constrs
                 (cons% ,element-exps ,element-types))))
       (arity (let* ((cons (second x))
                      (cons-recon (recon cons ctx defs))
                      (cons-type (first cons-recon))
                      (cons-constr (second cons-recon)))
                 `(i32 ,cons-constr (arity% ,cons-type))))
       (nth (let* ((idx (second x))
                   (cons (third x))
                   (cons-recon (recon cons ctx defs))
                   (cons-type (first cons-recon))
                   (cons-constr (second cons-recon))
                   (cons-exp (third cons-recon)))
              (if (integerp idx)
                  `((nth ,idx ,cons-type) ,cons-constr (nth% ,idx ,cons-exp))
                  (error 'satori-error :message "index not literal number"))))
       (quote (let* ((const (second x))
                     (expansion (expand-quote const))
                     (type (type-quote expansion)))
                `(,type nil (quote% ,expansion ,type))))
       (cast (let* ((union (second x))
                    (union-recon (recon union ctx defs))
                    (union-type (first union-recon))
                    (union-constrs (second union-recon))
                    (union-exp (third union-recon))
                    (clauses (rest (rest x)))
                    (types (map 'list #'first clauses))
                    (expanded-types (map 'list #'expand-type types))
                    (type-members (remove-duplicates expanded-types :test #'equal))
                    (type-union (if (= (length type-members) 1)
                                    (first type-members)
                                    `(union ,@type-members)))
                    (type-syms (wildcards-to-type-variable type-union))
                    (type-constrs `((,type-syms ,union-type)))
                    (bodies (map 'list #'second clauses))
                    (body-recons (map 'list #'(lambda (x) (recon x ctx defs)) bodies))
                    (body-types (map 'list #'first body-recons))
                    (body-members (remove-duplicates body-types :test #'equal))
                    (body-constrs (map 'list #'second body-recons))
                    (body-exps (map 'list #'third body-recons))
                    (clauses* (map 'list #'list expanded-types body-exps))
                    (rettype (if (= (length body-members) 1)
                                 (first body-members)
                                 `(union ,@body-members)))
                    (constrs (append type-constrs union-constrs body-constrs)))
               `(,rettype ,constrs (cast% (,union-exp ,union-type) ,@clauses*))))
       (t (let* ((f (first x))
                 (xs (rest x))
                 (recon-f (recon f ctx defs))
                 (recon-xs (map 'list #'(lambda (x) (recon x ctx defs)) xs))
                 (type-f (first recon-f))
                 (type-xs `((type-variable ,(gensym "T"))
                            . ,(map 'list #'first recon-xs)))
                 (constr-f (second recon-f))
                 (constr-xs (mappend #'second recon-xs))
                 (exp-f (third recon-f))
                 (exp-xs (map 'list #'third recon-xs))
                 (type-ret `(type-variable ,(gensym "T")))
                 (new-constr `((,type-f (lambda ,type-xs ,type-ret))))
                 (constr (append new-constr constr-f constr-xs)))
            `(,type-ret ,constr (,exp-f ,@exp-xs))))))))

(defun wildcards-to-type-variable (x)
  (cond ((eq x '*) `(type-variable ,(gensym)))
        ((atom x) x)
        (t (cons (wildcards-to-type-variable (first x))
                 (wildcards-to-type-variable (rest x))))))

(defun expand-type (ty)
  (cond ((listp ty) `(structure ,@(map 'list #'expand-type ty)))
        ((symbolp ty) ty)))

(defun type-quote (x)
  (cond ((integerp x) `(i32 ,x))
        ((and (listp x))
         `(structure ,@(map 'list #'type-quote (rest x))))
        ((symbolp x) `(symbol ,x))))

(defun expand-quote (x)
  (cond ((atom x) x)
        ((listp x) `(cons ,@(map 'list #'expand-quote x)))))

(defun lambdap (x)
  (and (listp x) (eq (first x) 'lambda)))

(defun isval (x)
  (cond
    ((integerp x) t)
    ((and (listp x)
          (case (first x)
            (lambda t)
            (lambda% t))))
    (t nil)))

(defun subst-type (tyX tyT tyS)
  (defun f (tyS)
    (cond
      ((equal tyS 'i1) 'i1)
      ((equal tyS 'i32) 'i32)
      ((case (first tyS)
         (nth tyS)
         (symbol tyS)
         (structure `(structure ,@(map 'list #'f (rest tyS))))
         (union `(union ,@(map 'list #'f (rest tyS))))
         (type-variable (let ((s (second tyS)))
                          (if (equal s tyX)
                              tyT
                              `(type-variable ,s))))
         (lambda (let ((tyS1 (second tyS))
                       (tyS2 (third tyS)))
                   `(lambda ,(map 'list #'f tyS1) ,(f tyS2))))))))
  (f tyS))

(defun apply-subst (constr tyT)
  (reduce #'(lambda (tyS x)
              (let ((tyX (second (first x)))
                    (tyC2 (second x)))
                (subst-type tyX tyC2 tyS)))
          (reverse constr)
          :initial-value tyT))

(defun subst-constr (tyX tyT constr)
  (map 'list
       #'(lambda (x)
           (let ((tyS1 (first x))
                 (tyS2 (second x)))
             `(,(subst-type tyX tyT tyS1) ,(subst-type tyX tyT tyS2))))
       constr))

(defun occurs-in (tyX tyT)
  (defun o (tyT)
    (cond
      ((equal tyT 'i1) nil)
      ((equal tyT 'i32) nil)
      ((case (first tyT)
         (type-variable (equal (second tyT) tyX))
         (lambda (let ((tyT1 (second tyT))
                       (tyT2 (third tyT)))
                   (or (o tyT1) (o tyT2))))))))
  (o tyT))

(defun gensymp (x)
  (and (symbolp x) (null (symbol-package x))))

(defun unify-match (x y)
  (cond
    ((or (eql x y)
         (and (listp x) (eq (first x) 'type-variable) (gensymp (second x)))) t)
    ((and (consp x) (consp y) (unify-match (car x) (car y)))
     (unify-match (cdr x) (cdr y)))
    (t nil)))

(defun unify (constr)
  (defun u (constr)
    (let ((fst (first (first constr)))
          (snd (second (first constr))))
      (cond
        ((null constr) nil)
        ((equal fst snd) (u (rest constr)))
        ((and (listp snd)
              (case (first snd)
                (type-variable
                 (let ((tyS fst)
                       (tyX (second snd)))
                   (cond
                     ((equal tyS `(type-variable ,tyX)) (u (rest constr)))
                     ((occurs-in tyX tyS)
                      (error 'satori-error :message "circular constraints"))
                     (t (append (u (subst-constr tyX tyS (rest constr)))
                                `(((type-variable ,tyX) ,tyS))))))))))
        ((and (listp fst)
              (case (first fst)
                (type-variable
                 (let ((tyX (second fst))
                       (tyT snd))
                   (cond
                     ((equal tyT `(type-variable ,tyX)) (u (rest constr)))
                     ((occurs-in tyX tyT) (error 'satori-error
                                                 :message "circular constraints"))
                     (t (append (u (subst-constr tyX tyT (rest constr)))
                                `(((type-variable ,tyX) ,tyT)))))))
                (lambda
                    (let* ((f1 fst)
                           (f2 snd)
                           (tyS1 (second f1))
                           (tyS2 (third f1))
                           (tyT1 (second f2))
                           (tyT2 (third f2))
                           (type-1s (map 'list
                                         #'(lambda (tyS1 tyT1)
                                             `(,tyS1 ,tyT1))
                                         tyS1
                                         tyT1)))
                      (u `(,@type-1s (,tyS2 ,tyT2) ,@(rest constr))))))))
        ((unify-match fst snd) (u (rest constr)))
        (t (error 'satori-error :message "unsolvable constraints")))))
  (u (remove-nil constr)))

(defun infer (x ctx constr)
  (let* ((recon (recon x ctx nil))
         (type (first recon)))
    (when type
      (let* ((exp (third recon))
             (constr* (unify (remove-nil (append constr (second recon))))))
        `(,(apply-subst constr* type) ,constr* ,exp)))))
