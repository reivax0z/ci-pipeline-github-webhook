#!/bin/bash

rm -rf package
mkdir package
pip2 install -r requirements.txt -t package
cp lambda_function.py package
cd package
zip -r ../ci-build-authorizer.zip *

