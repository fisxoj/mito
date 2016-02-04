(in-package :cl-user)
(defpackage mito-test.dao
  (:use #:cl
        #:prove
        #:mito.dao
        #:mito.connection
        #:mito-test.util))
(in-package :mito-test.dao)

(plan nil)

(subtest "dao-table-class inheritance"

  (when (find-class 'tweet nil)
    (setf (find-class 'tweet) nil))

  (defclass tweet () ()
    (:metaclass dao-table-class))

  (ok (find (find-class 'dao-class) (c2mop:class-direct-superclasses (find-class 'tweet)))
      "dao-table-class inherits dao-table implicitly")

  (defclass my-dao-class (dao-class) ())

  (defclass tweet (my-dao-class) ()
    (:metaclass dao-table-class))

  (ok (not (find (find-class 'dao-class) (c2mop:class-direct-superclasses (find-class 'tweet))))
      "Not inherit dao-class directly")
  (ok (find (find-class 'my-dao-class) (c2mop:class-direct-superclasses (find-class 'tweet)))
      "Inherit my-dao-class")

  (is-table-class :mysql
                  (defclass tweet ()
                    ((status :col-type :text)
                     (user :col-type :integer))
                    (:metaclass dao-table-class)
                    (:record-timestamps nil))
                  "CREATE TABLE tweet (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, status TEXT NOT NULL, user INTEGER NOT NULL)"
                  "auto-pk")

  (is-table-class :mysql
                  (defclass tweet ()
                    ((id :col-type :serial
                         :primary-key t)
                     (status :col-type :text)
                     (user :col-type :integer))
                    (:metaclass dao-table-class)
                    (:record-timestamps nil))
                  "CREATE TABLE tweet (id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, status TEXT NOT NULL, user INTEGER NOT NULL)"
                  "add original PK")

  (is-table-class :mysql
                  (defclass tweet ()
                    ((status :col-type :text)
                     (user :col-type :integer))
                    (:metaclass dao-table-class)
                    (:record-timestamps nil))
                  "CREATE TABLE tweet (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, status TEXT NOT NULL, user INTEGER NOT NULL)"
                  "redefinition w/o PK")

  (is-table-class :mysql
                  (defclass tweet ()
                    ((status :col-type :text)
                     (user :col-type :integer))
                    (:metaclass dao-table-class)
                    (:auto-pk nil)
                    (:record-timestamps nil))
                  "CREATE TABLE tweet (status TEXT NOT NULL, user INTEGER NOT NULL)"
                  "auto-pk is nil"))

(subtest "relation"
  (setf *connection* (connect-to-testdb :mysql))
  (when (find-class 'user nil)
    (setf (find-class 'user) nil))
  (when (find-class 'tweet nil)
    (setf (find-class 'tweet) nil))

  (defclass user ()
    ((id :col-type :serial
         :primary-key t)
     (name :col-type :text
           :initarg :name))
    (:metaclass dao-table-class)
    (:record-timestamps nil))

  (defclass tweet ()
    ((status :col-type :text
             :initarg :status
             :accessor tweet-status)
     (user :col-type user
           :initarg :user
           :accessor tweet-user))
    (:metaclass dao-table-class)
    (:record-timestamps nil))

  (is (sxql:yield (table-definition 'tweet))
      "CREATE TABLE tweet (id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, status TEXT NOT NULL, user_id INT UNSIGNED NOT NULL)")
  (mito:execute-sql "DROP TABLE IF EXISTS user")
  (mito:execute-sql "DROP TABLE IF EXISTS tweet")
  (mito:ensure-table-exists 'user)
  (mito:ensure-table-exists 'tweet)
  (let ((user (mito:create-dao 'user :name "Eitaro")))
    (mito:create-dao 'tweet :status "Hello" :user user))

  (let ((tweets (mito:select-dao 'tweet)))
    (is (length tweets) 1)
    (is-type (first tweets) 'tweet)
    (is-type (tweet-user (first tweets)) 'user))

  (disconnect-toplevel))

(finalize)
