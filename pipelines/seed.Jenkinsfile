pipeline {
    agent { label 'docker' }

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
    }

    parameters {
        string(
            name: 'GITHUB_ORG',
            defaultValue: 'meghana-devops-test',
            description: 'GitHub organization to scan'
        )
    }

    stages {
        stage('Checkout Assignment') {
            steps {
                deleteDir()

                git branch: 'main',
                    url: 'https://github.com/meghanareddy08/Txstate-DevOps-Assignment.git'
            }
        }

        stage('Discover Repositories') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'github-read-token',
                        variable: 'GITHUB_TOKEN'
                    )
                ]) {
                    sh '''
                        set -eu
                        python3 discovery/discover_repositories.py
                    '''
                }
            }
        }

        stage('Validate Inventory') {
            steps {
                sh '''
                    set -eu

                    test -s discovery/repositories.json

                    echo "Repositories discovered:"
                    jq 'length' discovery/repositories.json

                    echo "Buildable repositories:"
                    jq '[.[] | select(.buildable == true)] | length' \
                      discovery/repositories.json
                '''
            }
        }

        stage('Generate Repository Jobs') {
            steps {
                jobDsl(
                    targets: 'jobs/seed_job.groovy',
                    removedJobAction: 'DISABLE',
                    removedViewAction: 'IGNORE',
                    lookupStrategy: 'JENKINS_ROOT'
                )
            }
        }
    }

    post {
        success {
            echo 'Repository discovery and job generation completed successfully.'
        }

        failure {
            echo 'Seed pipeline failed. Previously generated jobs remain available.'
        }

        cleanup {
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}
