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
(build-utils:jar-file "lispcalls")
(build-utils:jar-file "slf4j-simple-1.7.25")
(build-utils:jar-file "slack-api-client-1.5.0-M1")
(build-utils:jar-file "jira-rest-java-client-app-5.2.2")
(build-utils:jar-file "jira-rest-java-client-core-5.2.2")
(build-utils:jar-file "trello-java-wrapper-0.14")
(build-utils:jar-file "slf4j-log4j12-1.7.10")
(build-utils:jar-file "jcl-over-slf4j-1.7.10")
(build-utils:jar-file "slf4j-api-1.7.30")
(build-utils:jar-file "aws-java-sdk-s3-1.11.875")
(build-utils:jar-file "org.eclipse.egit.github.core-5.10.0.202012080955-r")
(build-utils:jar-file "kotlin-stdlib-jdk8-1.4.10")
(build-utils:jar-file "commons-lang3-3.11")
(build-utils:jar-file "jira-rest-java-client-api-5.2.2")
(build-utils:jar-file "asana-0.10.3")
(build-utils:jar-file "java-jwt-3.12.0")
(build-utils:jar-file "bcprov-jdk15on-1.68")
(build-utils:jar-file "gitlab4j-api-4.15.7")
(build-utils:jar-file "selenium-java-3.141.59")
(build-utils:jar-file "json-20210307")
(build-utils:jar-file "aws-java-sdk-kms-1.11.875")
(build-utils:jar-file "aws-java-sdk-core-1.11.875")
(build-utils:jar-file "jmespath-java-1.11.875")
(build-utils:jar-file "slack-api-model-1.5.0-M1")
(build-utils:jar-file "selenium-chrome-driver-3.141.59")
(build-utils:jar-file "selenium-edge-driver-3.141.59")
(build-utils:jar-file "selenium-firefox-driver-3.141.59")
(build-utils:jar-file "selenium-ie-driver-3.141.59")
(build-utils:jar-file "selenium-opera-driver-3.141.59")
(build-utils:jar-file "selenium-safari-driver-3.141.59")
(build-utils:jar-file "selenium-support-3.141.59")
(build-utils:jar-file "selenium-remote-driver-3.141.59")
(build-utils:jar-file "okhttp-4.9.0")
(build-utils:jar-file "google-http-client-gson-1.20.0")
(build-utils:jar-file "gson-2.8.6")
(build-utils:jar-file "kotlin-stdlib-jdk7-1.4.10")
(build-utils:jar-file "okio-jvm-2.8.0")
(build-utils:jar-file "kotlin-stdlib-1.4.10")
(build-utils:jar-file "atlassian-util-concurrent-4.0.1")
(build-utils:jar-file "atlassian-httpclient-library-2.0.0")
(build-utils:jar-file "atlassian-httpclient-api-2.0.0")
(build-utils:jar-file "joda-time-2.9.9")
(build-utils:jar-file "guava-26.0-jre")
(build-utils:jar-file "google-oauth-client-1.20.0")
(build-utils:jar-file "google-http-client-1.20.0")
(build-utils:jar-file "jsr305-3.0.2")
(build-utils:jar-file "jersey-client-1.19")
(build-utils:jar-file "jersey-json-1.19")
(build-utils:jar-file "sal-api-3.0.7")
(build-utils:jar-file "atlassian-event-3.0.0")
(build-utils:jar-file "spring-beans-4.1.7.RELEASE")
(build-utils:jar-file "fugue-2.2.1")
(build-utils:jar-file "fugue-3.0.0")
(build-utils:jar-file "commons-cli-1.4")
(build-utils:jar-file "httpmime-4.5.7")
(build-utils:jar-file "jersey-apache-connector-2.30.1")
(build-utils:jar-file "httpasyncclient-cache-4.1.4")
(build-utils:jar-file "httpasyncclient-4.1.4")
(build-utils:jar-file "httpclient-cache-4.5.6")
(build-utils:jar-file "httpclient-4.5.9")
(build-utils:jar-file "spring-core-4.1.7.RELEASE")
(build-utils:jar-file "commons-logging-1.2")
(build-utils:jar-file "jackson-jaxrs-json-provider-2.10.3")
(build-utils:jar-file "jackson-jaxrs-base-2.10.3")
(build-utils:jar-file "jackson-module-jaxb-annotations-2.10.3")
(build-utils:jar-file "jackson-databind-2.10.5.1")
(build-utils:jar-file "jackson-dataformat-cbor-2.6.7")
(build-utils:jar-file "jackson-core-2.10.5")
(build-utils:jar-file "jackson-annotations-2.10.5")
(build-utils:jar-file "commons-codec-1.14")
(build-utils:jar-file "jakarta.xml.bind-api-2.3.2")
(build-utils:jar-file "jakarta.activation-api-1.2.2")
(build-utils:jar-file "jersey-hk2-2.30.1")
(build-utils:jar-file "jersey-client-2.30.1")
(build-utils:jar-file "jersey-media-multipart-2.30.1")
(build-utils:jar-file "jakarta.servlet-api-4.0.3")
(build-utils:jar-file "selenium-api-3.141.59")
(build-utils:jar-file "byte-buddy-1.8.15")
(build-utils:jar-file "commons-exec-1.3")
(build-utils:jar-file "ion-java-1.0.2")
(build-utils:jar-file "kotlin-stdlib-common-1.4.10")
(build-utils:jar-file "annotations-13.0")
(build-utils:jar-file "checker-qual-2.5.2")
(build-utils:jar-file "error_prone_annotations-2.1.3")
(build-utils:jar-file "j2objc-annotations-1.1")
(build-utils:jar-file "animal-sniffer-annotations-1.14")
(build-utils:jar-file "jersey-core-1.19")
(build-utils:jar-file "jettison-1.1")
(build-utils:jar-file "jaxb-impl-2.2.3-1")
(build-utils:jar-file "jackson-jaxrs-1.9.2")
(build-utils:jar-file "jackson-xc-1.9.2")
(build-utils:jar-file "jackson-mapper-asl-1.9.2")
(build-utils:jar-file "jackson-core-asl-1.9.2")
(build-utils:jar-file "log4j-1.2.17")
(build-utils:jar-file "jersey-common-2.30.1")
(build-utils:jar-file "hk2-locator-2.6.1")
(build-utils:jar-file "javassist-3.25.0-GA")
(build-utils:jar-file "jakarta.ws.rs-api-2.1.6")
(build-utils:jar-file "hk2-api-2.6.1")
(build-utils:jar-file "hk2-utils-2.6.1")
(build-utils:jar-file "jakarta.inject-2.6.1")
(build-utils:jar-file "mimepull-1.9.11")
(build-utils:jar-file "httpcore-nio-4.4.10")
(build-utils:jar-file "httpcore-4.4.11")
(build-utils:jar-file "jsr311-api-1.1.1")
(build-utils:jar-file "jaxb-api-2.2.2")
(build-utils:jar-file "jakarta.annotation-api-1.3.5")
(build-utils:jar-file "osgi-resource-locator-1.0.3")
(build-utils:jar-file "aopalliance-repackaged-2.6.1")
(build-utils:jar-file "stax-api-1.0-2")
(build-utils:jar-file "activation-1.1")
))
