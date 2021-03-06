(in-package #:satori)

(defun find-anywhere (item tree)
  (cond ((eql item tree) tree)
        ((atom tree) nil)
        ((find-anywhere item (first tree)))
        ((find-anywhere item (rest tree)))))

(defun sort-symbols< (list)
  (assert (every #'symbolp list))
  (let ((strings (map 'list #'string list)))
    (map 'list #'intern (sort strings #'string<))))

(defun flatten (structure)
  (cond
    ((null structure) nil)
    ((atom structure) (list structure))
    (t (mapcan #'flatten structure))))

(defun mappend (fn &rest lsts)
  (apply #'append (apply #'mapcar fn lsts)))

(defun unwrap (x)
  (cond
    ((not (listp x)) x)
    ((and (= (length x) 1) (atom (first x))) (first x))
    (t x)))

(defun remove-nil (x)
  (cond ((listp x) (map 'list #'remove-nil (remove nil x)))
        (t x)))

(defmacro aif (test &optional then else)
  (let ((win (gensym)))
    `(multiple-value-bind (it ,win) ,test
       (if (or it ,win) ,then ,else))))

(defmacro acond (&rest clauses)
  (if (null clauses)
      nil
      (let ((cl1 (car clauses))
            (val (gensym))
            (win (gensym)))
        `(multiple-value-bind (,val ,win) ,(car cl1)
           (if (or ,val ,win)
               (let ((it ,val))
                 ,@(cdr cl1))
               (acond ,@(cdr clauses)))))))

(defun structurep (x)
  (and (listp x) (eq (first x) 'structure)))

(defun unionp (x)
  (and (listp x) (eq (first x) 'union)))

