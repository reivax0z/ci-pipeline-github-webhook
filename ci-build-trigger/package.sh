#!/bin/bash

rm -rf package
mkdir package
cp lambda_function.py package
cd package
zip -r ../ci-build-trigger.zip *

