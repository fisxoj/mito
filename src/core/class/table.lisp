(in-package :cl-user)
(defpackage mito.class.table
  (:use #:cl
        #:mito.util)
  (:import-from #:mito.class.column
                #:table-column-class
                #:table-column-type
                #:table-column-name
                #:primary-key-p
                #:ghost-slot-p)
  (:import-from #:alexandria
                #:ensure-list)
  (:export #:table-class
           #:table-name
           #:table-column-slots
           #:table-direct-column-slots
           #:table-primary-key
           #:table-serial-key
           #:table-indices-info
           #:database-column-slots))
(in-package :mito.class.table)

(defclass table-class (standard-class)
  ((primary-key :initarg :primary-key
                :initform nil)
   (unique-keys :initarg :unique-keys
                :initform nil)
   (keys :initarg :keys
         :initform nil)
   (table-name :initarg :table-name
               :initform nil)))

(defmethod reinitialize-instance :around ((class table-class) &rest initargs)
  (unless (getf initargs :primary-key)
    (setf (getf initargs :primary-key) nil))
  (unless (getf initargs :unique-keys)
    (setf (getf initargs :unique-keys) nil))
  (unless (getf initargs :keys)
    (setf (getf initargs :keys) nil))
  (unless (getf initargs :table-name)
    (setf (getf initargs :table-name) nil))
  (apply #'call-next-method class initargs))

(defmethod c2mop:direct-slot-definition-class ((class table-class) &key)
  'table-column-class)

(defmethod c2mop:validate-superclass ((class table-class) (super standard-class))
  t)

(defgeneric table-name (class)
  (:method ((class table-class))
    (if (slot-value class 'table-name)
        (string (car (slot-value class 'table-name)))
        (let ((class-name (lispify (symbol-name-literally (class-name class)))))
          (unlispify
           (if (and (char= (aref class-name 0) #\<)
                    (char= (aref class-name (1- (length class-name))) #\>))
               (subseq class-name 1 (1- (length class-name)))
               class-name))))))

(defgeneric table-primary-key (class)
  (:method ((class table-class))
    (or (slot-value class 'primary-key)
        (let ((primary-slot (find-if
                             #'primary-key-p
                             (database-column-slots class))))
          (if primary-slot
              (list (c2mop:slot-definition-name primary-slot))
              nil)))))

(defgeneric table-serial-key (class)
  (:method ((class table-class))
    (let* ((primary-key (table-primary-key class))
           (slot (find-if
                  (lambda (slot)
                    (and
                     ;; AUTO INCREMENT slot
                     (member (table-column-type slot) '(:serial :bigserial)
                                 :test #'eq)
                     (member (c2mop:slot-definition-name slot)
                             primary-key :test #'eq)))
                  (database-column-slots class))))
      (if slot
          (c2mop:slot-definition-name slot)
          nil))))

(defun table-direct-column-slots (class)
  (remove-if-not (lambda (slot)
                   (typep slot 'table-column-class))
                 (c2mop:class-direct-slots class)))

(defun map-all-superclasses (fn class)
  (labels ((main (class &optional main-objects)
             (loop for superclass in (c2mop:class-direct-superclasses class)
                   if (eq (class-of superclass) (find-class 'standard-class))
                     append (if (eq superclass (find-class 'standard-object))
                                (append (funcall fn class) main-objects)
                                (funcall fn class))
                   else
                     append (main superclass
                                  (append (funcall fn class)
                                          main-objects)))))
    (delete-duplicates
     (main class)
     :test #'eq
     :from-end t)))

(defun table-column-slots (class)
  (map-all-superclasses #'table-direct-column-slots
                        class))

(defgeneric database-column-slots (class)
  (:method ((class table-class))
    (remove-if #'ghost-slot-p
               (table-column-slots class))))

(defgeneric table-indices-info (class driver-type)
  (:method (class driver-type)
    (let ((table-name (table-name class)))
      (flet ((unlispify-keys (keys)
               (if (listp keys)
                   (mapcar #'string (mapcar #'unlispify keys))
                   (string (unlispify keys)))))
        (append
         (when (slot-value class 'primary-key)
           (let ((primary-keys (slot-value class 'primary-key)))
             (list
              (list (format nil "~A_pkey" table-name)
                    :unique-key t
                    :primary-key t
                    :columns (unlispify-keys primary-keys)))))
         ;; See also :primary-key column
         (let ((primary-key-slot (find-if #'primary-key-p (database-column-slots class))))
           (when primary-key-slot
             (list
              (list (format nil "~A_pkey" table-name)
                    :unique-key t
                    :primary-key t
                    :columns (unlispify-keys (list (table-column-name primary-key-slot)))))))

         (let ((unique-keys (map-all-superclasses (lambda (class)
                                                    (slot-value class 'unique-keys))
                                                  class)))
           (when unique-keys
             (mapcar (lambda (key)
                       ;; FIXME: it'll raise an error if the index name is too long
                       (list (format nil "unique_~A_~{~A~^_~}"
                                     table-name
                                     (unlispify-keys (ensure-list key)))
                             :unique-key t
                             :primary-key nil
                             :columns (ensure-list (unlispify-keys key))))
                     unique-keys)))
         ;; Ignore :keys when using SQLite3
         (unless (eq driver-type :sqlite3)
           (let ((keys (map-all-superclasses (lambda (class)
                                               (slot-value class 'keys))
                                             class)))
             (when keys
               (mapcar (lambda (key)
                         ;; FIXME: it'll raise an error if the index name is too long
                         (list (format nil "key_~A_~{~A~^_~}"
                                       table-name
                                       (unlispify-keys (ensure-list key)))
                               :unique-key nil
                               :primary-key nil
                               :columns (ensure-list (unlispify-keys key))))
                       keys)))))))))
