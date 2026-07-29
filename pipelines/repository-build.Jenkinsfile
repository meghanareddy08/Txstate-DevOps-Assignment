pipeline {
    agent { label 'docker' }

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'REPO_NAME', description: 'Repository name')
        string(name: 'REPO_FULL_NAME', description: 'Organization/repository')
        string(name: 'REPO_URL', description: 'Git clone URL')
        string(name: 'REPO_BRANCH', defaultValue: 'main', description: 'Branch to build')
    }

    environment {
        REGISTRY = 'localhost:5000'
    }

    stages {
        stage('Checkout') {
            steps {
                deleteDir()

                git branch: params.REPO_BRANCH,
                    url: params.REPO_URL
            }
        }

        stage('Validate Repository') {
            steps {
                sh '''
                    set -eu

                    if [ ! -f Dockerfile ]; then
                        echo "ERROR: Root-level Dockerfile is missing."
                        exit 1
                    fi
                '''
            }
        }

        stage('Test Gate') {
            steps {
                sh '''
                    set -eu

                    if [ -f test.sh ]; then
                        echo "Root-level test.sh found. Running tests..."
                        sh test.sh
                    else
                        echo "No root-level test.sh found. Continuing to build."
                    fi
                '''
            }
        }

        stage('Prepare Image Metadata') {
            steps {
                script {
                    env.GIT_SHORT_SHA = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_REPOSITORY =
                        "${env.REGISTRY}/${params.REPO_FULL_NAME.toLowerCase()}"

                    env.IMAGE_SHA =
                        "${env.IMAGE_REPOSITORY}:${env.GIT_SHORT_SHA}"

                    env.IMAGE_BUILD =
                        "${env.IMAGE_REPOSITORY}:build-${env.BUILD_NUMBER}"
                }

                echo "Image SHA tag: ${env.IMAGE_SHA}"
                echo "Image build tag: ${env.IMAGE_BUILD}"
            }
        }

        stage('Build Image') {
            steps {
                sh '''
                    set -eu

                    docker build \
                      --label org.opencontainers.image.revision="$GIT_SHORT_SHA" \
                      --label org.opencontainers.image.source="$REPO_URL" \
                      --tag "$IMAGE_SHA" \
                      --tag "$IMAGE_BUILD" \
                      .
                '''
            }
        }

        stage('Push Image') {
            steps {
                sh '''
                    set -eu

                    docker push "$IMAGE_SHA"
                    docker push "$IMAGE_BUILD"
                '''
            }
        }
    }

    post {
        success {
            echo "Successfully built and published ${env.IMAGE_SHA}"
        }

        failure {
            echo "Pipeline failed. Images were not published unless the failure occurred during push."
        }

        cleanup {
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}
