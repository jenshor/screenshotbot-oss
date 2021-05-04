
def doCheckout () {
    checkout([
        $class: 'GitSCM',
        branches: [[name: env.GIT_SHA ]],
        doGenerateSubmoduleConfigurations: false,
        extensions: [[$class: 'SubmoduleOption',
                      disableSubmodules:false,
                      parentCredentials: true,
                      recursiveSubmodules:true,
                      reference:'',
                      trackingSubmodules:false]],
        submoduleCfg: [],
        userRemoteConfigs: [[credentialsId: 'jenkins-root', url: 'https://github.com/screenshotbot/screenshotbot-oss.git']]
    ]
    )
}

def cleanRepo () {
    doCheckout()
    sh "git clean -ffd"
    sh "make clean-sys-index"
    sh "git submodule init && git submodule update"
    // Some debugging information to make sure
    // we're doing this pipeline correctly.
    sh "git status"
}

pipeline {
    agent {
        label 'master';
    }

    stages {

        stage ("Checkout on primary") {
            steps {
                doCheckout()
                //stash 'source'
            }
        }

        stage("Run tests in parallel") {


            parallel {
                stage("run on Lispworks") {
                    agent {
                        label 'master'
                    }
                    steps {
                        //unstash 'source'
                        cleanRepo()
                        sh "make test-lw"
                        sh "test -f src/screenshotbot.oss.tests.asd || make test-store"
                        sh "test -f src/screenshotbot.oss.tests.asd || make web-bin"
                    }
                }

                stage("Selenium tests") {
                    agent {
                        label 'master'
                    }
                    steps {
                        //unstash 'source'
                        cleanRepo()
                        sh "test -f src/screenshotbot.oss.tests.asd || make selenium-tests"
                    }
                }

                stage ("test on SBCL") {
                    agent any
                    steps {
                        //unstash 'source'

                        cleanRepo()
                        sh "make update-quicklisp"
                        sh "make test-sb"
                    }
                }

                stage("run on CCL") {
                    agent any
                    steps {
                        //unstash 'source'
                        cleanRepo()
                        sh "make test-ccl"
                    }
                }

                stage ("Copybara") {
                    steps {
                        sh "test -f src/screenshotbot.oss.tests.asd || make conditional-copybara"
                    }
                }
            }
        }

        stage ('Deploy') {
            when {
                expression {
                    return params.DIFF_ID == ""
                }
            }

            parallel {
                stage('Deploy - Linux SDK') {
                    agent {
                        label 'master'
                    }

                    steps {
                        cleanRepo()
                        sh "make build/lw-console"
                        sh "build/lw-console -build scripts/deliver-sdk.lisp"
                        stash includes: "build/screenshotbot-sdk-installer-linux.sh", name "screenshotbot-sdk-installer-linux"
                    }
                }

                stage('Deploy - Mac SDK') {
                    agent {
                        label 'mac'
                    }

                    steps {
                        cleanRepo()
                        sh "make build/lw-console"
                        sh "build/lw-console -build scripts/deliver-sdk.lisp"
                        stash includes: "build/screenshotbot-sdk-installer-mac.sh", name "screenshotbot-sdk-installer-mac"
                    }
                }

                stage ("Copy artifacts to destination") {
                    // Quick sanity check
                    sh "[ `hostname` = thecharmer ]"

                    unstash "screenshotbot-sdk-installer-linux"
                    unstash "screenshotbot-sdk-installer-mac"
                }
            }
        }
    }
    post {
        success {
            sh "test -f src/screenshotbot.oss.tests.asd || make update-harbormaster-pass"
        }

        failure {
            sh "test -f src/screenshotbot.oss.tests.asd || make update-harbormaster-fail"
        }
    }
}
