;; Autogenerated: do not modify
(defpackage :java.libs-asdf
  (:use :cl :asdf))
(in-package :java.libs-asdf)

(eval-when (:compile-toplevel :load-toplevel :execute)
   (unless (find-package :build-utils)
     (asdf:operate 'asdf:load-op :build-utils)
     (use-package :build-utils)))

(defsystem java.libs
   :class build-utils:java-library
   :defsystem-depends-on (:build-utils)
   :components (
(build-utils:jar-file "slf4j-simple-1.7.25")
(build-utils:jar-file "jira-rest-java-client-core-5.2.4")
(build-utils:jar-file "trello-java-wrapper-0.14")
(build-utils:jar-file "slf4j-api-1.7.30")
(build-utils:jar-file "org.eclipse.egit.github.core-5.10.0.202012080955-r")
(build-utils:jar-file "commons-lang3-3.11")
(build-utils:jar-file "jira-rest-java-client-api-5.2.4")
(build-utils:jar-file "fugue-4.7.2")
(build-utils:jar-file "asana-0.10.3")
(build-utils:jar-file "bcprov-jdk15on-1.68")
(build-utils:jar-file "json-20210307")
(build-utils:jar-file "atlassian-util-concurrent-4.0.1")
(build-utils:jar-file "atlassian-httpclient-library-2.1.5")
(build-utils:jar-file "atlassian-httpclient-api-2.1.5")
(build-utils:jar-file "joda-time-2.9.9")
(build-utils:jar-file "guava-30.1.1-jre")
(build-utils:jar-file "google-http-client-gson-1.20.0")
(build-utils:jar-file "google-oauth-client-1.20.0")
(build-utils:jar-file "google-http-client-1.20.0")
(build-utils:jar-file "jsr305-3.0.2")
(build-utils:jar-file "jersey-client-2.35")
(build-utils:jar-file "jersey-media-json-jettison-2.35")
(build-utils:jar-file "sal-api-4.4.2")
(build-utils:jar-file "atlassian-event-4.1.1")
(build-utils:jar-file "spring-beans-5.3.6")
(build-utils:jar-file "httpmime-4.5.13")
(build-utils:jar-file "httpasyncclient-cache-4.1.4")
(build-utils:jar-file "httpclient-cache-4.5.13")
(build-utils:jar-file "httpasyncclient-4.1.4")
(build-utils:jar-file "httpclient-4.5.13")
(build-utils:jar-file "commons-codec-1.15")
(build-utils:jar-file "gson-2.3.1")
(build-utils:jar-file "commons-logging-1.2")
(build-utils:jar-file "jackson-databind-2.9.8")
(build-utils:jar-file "jackson-core-2.9.8")
(build-utils:jar-file "jackson-annotations-2.9.8")
(build-utils:jar-file "failureaccess-1.0.1")
(build-utils:jar-file "listenablefuture-9999.0-empty-to-avoid-conflict-with-guava")
(build-utils:jar-file "checker-qual-3.8.0")
(build-utils:jar-file "error_prone_annotations-2.5.1")
(build-utils:jar-file "j2objc-annotations-1.3")
(build-utils:jar-file "jersey-media-jaxb-2.35")
(build-utils:jar-file "jersey-common-2.35")
(build-utils:jar-file "jakarta.ws.rs-api-2.1.6")
(build-utils:jar-file "jakarta.inject-2.6.1")
(build-utils:jar-file "jettison-1.3.7")
(build-utils:jar-file "spring-core-5.3.6")
(build-utils:jar-file "jakarta.annotation-api-1.3.5")
(build-utils:jar-file "osgi-resource-locator-1.0.3")
(build-utils:jar-file "spring-jcl-5.3.6")
(build-utils:jar-file "httpcore-nio-4.4.10")
(build-utils:jar-file "httpcore-4.4.13")
))
