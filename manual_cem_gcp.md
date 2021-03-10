# Deploy CEM Service on GCP

## Set Project ID
```
export PROJECT_ID=<PROJECT ID>
````

## Check Existing Deployment
```
export SERVICE_ACCOUNT_NAME=cem-service-account
export SERVICE_ACCOUNT_ID=cyb-cem
export SERVICE_ACCOUNT_CONFIG_FILE=cem_service_account.yml
export CEM_SINK_NAME=cem-sink
export CEM_DATASET_NAME=cem_logs_dataset

gcloud config set project ${PROJECT_ID} 

for line in $(gcloud deployment-manager deployments list); do
    if [[ "${line}" == "cem-service-account" ]]; then
        cat << EOF
            ERROR: 'cem-service-account' deployment already exists.
            Please delete 'cem-service-account' deployment and all its resources and try again
        EOF
        exit 1
    fi
done
```

## Run Deployment Steps

### 1. Set cloud shell project project_id
```
gcloud config set project ${PROJECT_ID} 
```

### 2. Enable APIs
```
echo "Enabling deploymentmanager, IAM ,cloudresourcemanager and bigQuery APIs..."
gcloud services enable deploymentmanager.googleapis.com \
cloudresourcemanager.googleapis.com \
iam.googleapis.com \
bigquery.googleapis.com \
recommender.googleapis.com
```

### 3. Add permissions to google serviceaccount
```
echo "Adding google serviceaccount permissions..."
gserviceaccount=$(gcloud projects get-iam-policy \
${PROJECT_ID} | grep -m 1 -Po 'serviceAccount:[0-9]+@cloudservices.gserviceaccount.com')

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member ${gserviceaccount} \
--role roles/iam.securityAdmin 

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member ${gserviceaccount} \
--role roles/iam.roleAdmin 
```

### 4. Create deployment
```
echo "Creating CEM service account deployment..."
gcloud deployment-manager deployments create ${SERVICE_ACCOUNT_NAME} \
--config ${SERVICE_ACCOUNT_CONFIG_FILE} 2> /dev/null
```

### 5. Add iam policy binding to the service account
```
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
--role projects/${PROJECT_ID}/roles/CustomCEMRole

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${SERVICE_ACCOUNT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
--role roles/bigquery.jobUser 
```

### 6. Create bigQuery dataset
```
echo "Creating bigQuery dataset..."
bq mk ${CEM_DATASET_NAME}
```

### 7. Create sink that export all logs tox BigQuery
```
echo "Creating Sink with bigQuery destination..."
gcloud logging sinks create ${CEM_SINK_NAME} \
bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${CEM_DATASET_NAME} \
--log-filter="NOT resource.type: k8s" --quiet
```

### 8. Get all details about cem-sink
```
cemsinkservice=$(gcloud beta logging sinks describe ${CEM_SINK_NAME} |grep -m 1 -Po 'p[0-9]+-[0-9]+' )
```

### 9. Set IAM permission to sink service account
```
echo "Adding sink serviceaccount permissions..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${cemsinkservice}@gcp-sa-logging.iam.gserviceaccount.com \
--role roles/bigquery.dataEditor
```

### 10. Set IAM permission to sink service account
```
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
--member serviceAccount:${cemsinkservice}@gcp-sa-logging.iam.gserviceaccount.com \
--role roles/logging.logWriter 
```

### 11. Update sink with the new roles
```
echo "Update sink..."
gcloud logging sinks update  ${CEM_SINK_NAME} bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${CEM_DATASET_NAME}
```
