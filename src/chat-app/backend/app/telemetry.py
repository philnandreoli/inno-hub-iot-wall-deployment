import logging
import os

logger = logging.getLogger(__name__)


def configure_telemetry() -> None:
    """Configure Azure Monitor OpenTelemetry for Application Insights.

    Reads the connection string from the APPLICATIONINSIGHTS_CONNECTION_STRING
    environment variable.  When the variable is empty or missing, telemetry is
    silently disabled so the app still starts in local-dev scenarios.
    """
    connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING", "").strip()
    if not connection_string:
        logger.info("APPLICATIONINSIGHTS_CONNECTION_STRING not set — telemetry disabled")
        return

    try:
        from azure.monitor.opentelemetry import configure_azure_monitor

        configure_azure_monitor(
            connection_string=connection_string,
            enable_live_metrics=True,
        )
        logger.info("Azure Monitor OpenTelemetry configured")
    except Exception:
        logger.exception("Failed to configure Azure Monitor OpenTelemetry — continuing without telemetry")
