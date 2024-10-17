import os
from azure.storage.blob import BlobServiceClient

# Azure Blob storage connection string and container name
connect_str = 'DefaultEndpointsProtocol=https;AccountName=fontysdata;AccountKey=####;EndpointSuffix=core.windows.net'
container_name = 'banking'

blob_service_client = BlobServiceClient.from_connection_string(connect_str)

try:
    container_client = blob_service_client.create_container(container_name)
except Exception as e:
    print(f"Container already exists: {e}")

def upload_to_azure(local_file_path):
    blob_name = f'data_backup_{os.path.basename(local_file_path)}'
    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)

    with open(local_file_path, "rb") as data:
        blob_client.upload_blob(data, overwrite=True)

    return blob_name
