#!/bin/bash -e

declare credential_aws_account_id
declare pipeline_name
declare target_s3_bucket
declare target_s3_prefix

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
  echo "INFO: Checking aws connectivity..."
  set +e
  if ! aws sts get-caller-identity > /dev/null
  then
    echo "ERROR: Error accessing AWS."
    echo "ERROR: Please make sure credentials are set properly. (Have you run 'aws configure'?)"
    exit 1
  fi
  set -e
}

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

function create_config_bucket() {
  aws s3 mb "s3://${target_s3_bucket}"
}

function build_and_upload_dependency() {
  local dependency="$1"
  cd ./"${dependency}"
  ./package.sh
  aws s3 cp \
    ./"${dependency}".zip \
    "s3://${target_s3_bucket}/${target_s3_prefix}/${dependency}.zip"
  cd ..
}

function main() {
  # Check credentials are provided
  check_aws_connectivity

  credential_aws_account_id=$(aws sts get-caller-identity \
    --query 'Account' \
    --output text)

  pipeline_name="${git_repo}-github-webhook"
  target_s3_bucket="${credential_aws_account_id}-build-resources"
  target_s3_prefix="${git_repo}-ci-pipeline"

  echo "INFO: Requesting to deploy '${pipeline_name}' for '${git_company}' in '${credential_aws_account_id}'"

  # Prepare config
  create_config_bucket

  # Auto install, zip & upload the dependencies (Lambda, CodeBuild...)
  build_and_upload_dependency "ci-build-config"
  build_and_upload_dependency "ci-build-authorizer"
  build_and_upload_dependency "ci-build-trigger"

  # Prepare Cloudformation stack
  aws cloudformation package \
    --template-file ./ci-build-stack.yml \
    --s3-bucket "${target_s3_bucket}" \
    --s3-prefix "${target_s3_prefix}" \
    --output-template-file ./output_template.yml

  # Deploy the stack (API Gateway, Lambdas...)
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
}

main
