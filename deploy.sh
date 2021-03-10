#!/usr/bin/env bash
set -e   # set -o errexit
set -u   # set -o nounset
set -o pipefail
[ "x${DEBUG:-}" = "x" ] || set -x

__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_ID=
SERVICE_ACCOUNT_NAME=cem-service-account
SERVICE_ACCOUNT_ID=cyb-cem
SERVICE_ACCOUNT_CONFIG_FILE=cem_service_account.yml
CEM_SINK_NAME=cem-sink
CEM_DATASET_NAME=cem_logs_dataset

function ShowUsage
{
    echo "Usage: $0 -p PROJECT_ID"
}

while getopts p:h o
do  case "$o" in
  p)  PROJECT_ID="$OPTARG";;
  [?] | h) ShowUsage ; exit 1;;
  esac
done


if [[ "${PROJECT_ID}" == "PROJECT_ID" ]]; then
  ShowUsage
  exit 1
fi

if [[ -z "${PROJECT_ID}" ]]; then
  ShowUsage
  exit 1
fi

function PrintSrviceAccountError
{
cat << EOF
    ERROR: 'cem-service-account' deployment already exists.
    Please delete 'cem-service-account' deployment and all its resources and try again
EOF
}

function PrintCustomRoleError
{
cat << EOF
    ERROR: 'CustomCEMRole' custom role already exists.
    Please delete 'CustomCEMRole' custom role and try again.
EOF
}


function CheckExistingDeployment
{
    # Set cloud shell project project_id
    gcloud config set project ${PROJECT_ID} > /dev/null 2>&1

    for line in $(gcloud deployment-manager deployments list); do
        if [[ "${line}" == "cem-service-account" ]]; then
            PrintSrviceAccountError
            exit 1
        fi
    done

    # check for cem role existence
    # gcloud beta iam roles --project ${PROJECT_ID} describe CustomCEMRole > /dev/null 2>&1
}

function RunDeploymentSteps
{
    # Set cloud shell project project_id
    gcloud config set project ${PROJECT_ID} > /dev/null 2>&1

    # Enable APIs
    echo "Enabling deploymentmanager, IAM ,cloudresourcemanager and bigQuery APIs..."
    gcloud services enable deploymentmanager.googleapis.com \
    cloudresourcemanager.googleapis.com \
    iam.googleapis.com \
    bigquery.googleapis.com \
    recommender.googleapis.com

    # add permissions to google serviceaccount
    echo "Adding google serviceaccount permissions..."
    gserviceaccount=$(gcloud projects get-iam-policy \
    ${PROJECT_ID} | grep -m 1 -Po 'serviceAccount:[0-9]+@cloudservices.gserviceaccount.com')

    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member ${gserviceaccount} \
    --role roles/iam.securityAdmin > /dev/null 2>&1

    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member ${gserviceaccount} \
    --role roles/iam.roleAdmin > /dev/null 2>&1

    # Create deployment
    echo "Creating CEM service account deployment..."
    gcloud deployment-manager deployments create ${SERVICE_ACCOUNT_NAME} \
    --config ${SERVICE_ACCOUNT_CONFIG_FILE} 2> /dev/null

    # Add iam policy binding to the service account
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role projects/${PROJECT_ID}/roles/CustomCEMRole

    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/bigquery.jobUser > /dev/null 2>&1

    # Create bigQuery dataset
    echo "Creating bigQuery dataset..."
    bq mk ${CEM_DATASET_NAME}

    # Create sink that export all logs tox BigQuery
    echo "Creating Sink with bigQuery destination..."
    gcloud logging sinks create ${CEM_SINK_NAME} \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${CEM_DATASET_NAME} \
    --log-filter="NOT resource.type: k8s" --quiet

    #Get all details about cem-sink
    cemsinkservice=$(gcloud beta logging sinks describe ${CEM_SINK_NAME} |grep -m 1 -Po 'p[0-9]+-[0-9]+' )

    #Set IAM permission to sink service account
    echo "Adding sink serviceaccount permissions..."
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:${cemsinkservice}@gcp-sa-logging.iam.gserviceaccount.com \
    --role roles/bigquery.dataEditor > /dev/null 2>&1

    #Set IAM permission to sink service account
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:${cemsinkservice}@gcp-sa-logging.iam.gserviceaccount.com \
    --role roles/logging.logWriter > /dev/null 2>&1

    #Update sink with the new roles
    echo "Update sink..."
    gcloud logging sinks update  ${CEM_SINK_NAME} bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${CEM_DATASET_NAME}

}

CheckExistingDeployment
RunDeploymentSteps
