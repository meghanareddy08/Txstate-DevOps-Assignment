import groovy.json.JsonSlurper

def inventoryText = readFileFromWorkspace(
    'discovery/repositories.json'
)

def repositories = new JsonSlurper().parseText(inventoryText)

def buildableRepositories = repositories.findAll {
    it.buildable == true
}

println "Creating or updating ${buildableRepositories.size()} repository jobs"

buildableRepositories.each { repo ->
    def safeJobName = repo.full_name
        .toLowerCase()
        .replaceAll('[^a-z0-9._-]+', '-')

    pipelineJob("repository-builds/${safeJobName}") {
        description(
            """Automatically generated build pipeline for ${repo.full_name}.
This job is managed by the repository-discovery seed job."""
        )

        keepDependencies(false)

        logRotator {
            numToKeep(20)
            artifactNumToKeep(5)
        }

        parameters {
            stringParam(
                'REPO_NAME',
                repo.name as String,
                'Repository name'
            )

            stringParam(
                'REPO_FULL_NAME',
                repo.full_name as String,
                'GitHub organization and repository'
            )

            stringParam(
                'REPO_URL',
                repo.clone_url as String,
                'Git clone URL'
            )

            stringParam(
                'REPO_BRANCH',
                (repo.default_branch ?: 'main') as String,
                'Branch to build'
            )
        }

        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url(
                                'https://github.com/meghanareddy08/Txstate-DevOps-Assignment.git'
                            )
                        }

                        branch('*/main')
                    }
                }

                scriptPath(
                    'pipelines/repository-build.Jenkinsfile'
                )

                lightweight(true)
            }
        }

        disabled(false)
    }
}

println 'Repository job generation completed'
