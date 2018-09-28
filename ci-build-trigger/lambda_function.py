#!/usr/bin/env python
'''
Parse a GitHub webhook event and triggers a Codebuild accordingly
'''

# Built-in libraries
from __future__ import print_function

# Libraries included in Lambda's environment
# See https://gist.github.com/gene1wood/4a052f39490fae00e0c3
import os
import boto3

def start_new_build(branch, commit):
    codebuild_client = boto3.client('codebuild')

    return codebuild_client.start_build(
        projectName=os.environ['CODEBUILD_PROJECT_NAME'],
        environmentVariablesOverride=[
            {
                'name': 'GIT_ACCOUNT',
                'value': os.environ['GIT_ACCOUNT'],
                'type': 'PLAINTEXT'
            },
            {
                'name': 'GIT_REPO',
                'value': os.environ['GIT_REPO'],
                'type': 'PLAINTEXT'
            },
            {
                'name': 'GIT_BRANCH',
                'value': branch,
                'type': 'PLAINTEXT'
            },
            {
                'name': 'GIT_COMMIT',
                'value': commit,
                'type': 'PLAINTEXT'
            },
        ]
    )

def lambda_handler(event, context):
    try:
        print(event)

        # Check the event payload type (only supporting new PR and PUSH events)
        event_type = event['headers']['X-GitHub-Event']

        if event_type == 'pull_request':

            action_type = event['body']['action']

            # PR Action can be one of:
            # "assigned", "unassigned", "review_requested", "review_request_removed",
            # "labeled", "unlabeled", "opened", "edited", "closed", or "reopened"

            # Note that the closed can represent a PR merge or a simple PR close event

            if action_type == 'opened' or action_type == 'reopened':

                branch = event['body']['pull_request']['head']['ref']
                commit = event['body']['pull_request']['head']['sha']

                print('Detected NEW_PR: branch=' + branch + ', sha=' + commit + ', starting new build')
                build = start_new_build(branch=branch, commit=commit)
                print('Codebuild started, buildId=' + build['build']['id'])

            else:
                print('Pass through event')

        elif event_type == 'push':

            # Detect branch deletion, no build request
            if event['body']['deleted'] == True:
                print('Pass through event')
                return

            branch = event['body']['ref'][len('refs/heads/'):]
            commit = event['body']['after']

            print('Detected PUSH: branch=' + branch + ', sha=' + commit + ', starting new build')
            build = start_new_build(branch=branch, commit=commit)
            print('Codebuild started, buildId=' + build['build']['id'])

        else:
            print('Pass through event')

    except Exception as ex:
        print(ex)
        raise
