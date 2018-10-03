#!/bin/bash -e

function usage() {
  echo ""
  echo "Usage"
  echo "./setup.sh \\"
  echo "    -c|--company <company> \\"
  echo "    -r|--repo <repository> \\"
  echo "    [-h|--help]"
  echo ""
  echo "Options"
  echo "-c | --company          The name under the Github account"
  echo "-r | --repo             The name of the Github repository"
  echo "-h | --help             (Optional) Display this help text"
  echo ""
}

function check_aws_connectivity() {
  echo "Checking aws connectivity..."
  set +e
  if ! aws sts get-caller-identity > /dev/null
  then
    echo "Error accessing AWS."
    echo "Please make sure credentials are set properly. (Have you run 'aws configure'?)"
    exit 1
  fi
  set -e
}

# Check credentials are provided
check_aws_connectivity

# Process script arguments
while [ ! $# -eq 0 ]
do
  case "${1}" in
    -c | --company)
      git_company="${2}"
      shift 2
      ;;
    -r | --repo)
      git_repo="${2}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown option (${1})! See usage (--help) for details" >&2
      usage
      exit 1
      ;;
    *)
      echo "ERROR: Unknown option (${1})! See usage (--help) for details" >&2
      usage
      exit 1
      ;;
  esac
done

credential_aws_account_id=$(aws sts get-caller-identity \
  --query 'Account' \
  --output text)

pipeline_name="${git_repo}-github-webhook"
target_s3_bucket="${credential_aws_account_id}-build-resources"
target_s3_prefix="${git_repo}-ci-pipeline"

echo "INFO: Requesting to deploy '${pipeline_name}' for '${git_company}' in '${credential_aws_account_id}'"

# TODO: create S3 bucket if not exist
function build_and_upload_dependency() {
  dependency="$1"
  cd ./"${dependency}"
  ./package.sh
  aws s3 cp \
    ./"${dependency}".zip \
    "s3://${target_s3_bucket}/${target_s3_prefix}/${dependency}.zip" \
    --sse 'aws:kms' \
    --sse-kms-key-id 'alias/aws/s3'
  cd ..
}

# Auto install, zip & upload the dependencies (Lambda, CodeBuild...)
build_and_upload_dependency "ci-build-config"
build_and_upload_dependency "ci-build-authorizer"
build_and_upload_dependency "ci-build-trigger"

# Prepare Cloudformation
aws cloudformation package \
  --template-file ./ci-build-stack.yml \
  --s3-bucket "${target_s3_bucket}" \
  --s3-prefix "${target_s3_prefix}" \
  --kms-key-id 'alias/aws/s3' \
  --output-template-file ./output_template.yml

# Spin up the entire stack
aws cloudformation deploy \
  --stack-name "${pipeline_name}" \
  --template-file ./output_template.yml \
  --capabilities 'CAPABILITY_IAM' \
  --parameter-overrides \
      S3BucketName="${target_s3_bucket}" \
      CodeS3PrefixConfig="${target_s3_prefix}" \
      GitAccount="${git_company}"
      GitRepository="${git_repo}"

echo "INFO: Successfully deployed '${pipeline_name}' for '${git_company}' in '${credential_aws_account_id}'"
