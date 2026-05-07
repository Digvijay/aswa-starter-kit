import os
import sys
import json
import logging
from datetime import datetime, timezone

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.cosmos import CosmosClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

ENDPOINT = os.environ.get("COSMOS_ENDPOINT")
DATABASE = os.environ.get("COSMOS_DATABASE", "app")
CONTAINER = os.environ.get("COSMOS_CONTAINER", "items")

_container = None


def _get_container():
    global _container
    if _container is None and ENDPOINT:
        client = CosmosClient(ENDPOINT, credential=DefaultAzureCredential())
        _container = client.get_database_client(DATABASE).get_container_client(CONTAINER)
    return _container


@app.route(route="status", methods=["GET"])
def status(req: func.HttpRequest) -> func.HttpResponse:
    cosmos = {"connected": False}
    try:
        c = _get_container()
        if c is not None:
            list(c.query_items(
                query="SELECT VALUE COUNT(1) FROM c",
                enable_cross_partition_query=True,
            ))
            cosmos = {"connected": True, "database": DATABASE, "container": CONTAINER}
    except Exception as ex:  # noqa: BLE001
        logging.exception("Cosmos check failed")
        cosmos = {"connected": False, "error": str(ex)}

    body = {
        "runtime": "python",
        "version": sys.version.split(" ")[0],
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "cosmos": cosmos,
    }
    return func.HttpResponse(
        json.dumps(body), mimetype="application/json", status_code=200
    )
