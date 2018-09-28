#!/usr/bin/env python
'''
Authorizes requests to API Gateway based on valid IP ranges (coming from GitHub servers).
For more information, see: https://help.github.com/articles/about-github-s-ip-addresses/
'''

from __future__ import print_function
import boto3
import json

# Libraries to include in our package
import requests
from netaddr import IPNetwork, IPAddress

def is_valid_github_address(address):
    ssm_client = boto3.client('ssm')
    token = ssm_client.get_parameter(Name='GitHubOAuthToken', WithDecryption=True)
    print('Retrieved GitHub oauth token from SSM')

    headers = {'Authorization': 'OAuth ' + token['Parameter']['Value']}
    response = requests.get('https://api.github.com/meta', headers=headers)
    github_info = json.loads(response.text)
    print(github_info)

    for range in github_info['hooks']:
        if IPAddress(address) in IPNetwork(range):
            return True
    return False

def lambda_handler(event, context):
    print(event)

    try:
        client_ip = event["requestContext"]["identity"]["sourceIp"]

        if not is_valid_github_address(address=client_ip):
            print('Invalid IP address, received: ' + client_ip)
            raise Exception('Unauthorized')

        # authorize
        return {
            'principalId': '*',
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [
                    {
                        'Action': 'execute-api:Invoke',
                        'Effect': 'Allow',
                        'Resource': event['methodArn']
                    }
                ]
            }
        }

    except Exception as ex:
        print(ex)
        raise
