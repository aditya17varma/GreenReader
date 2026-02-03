import json
import logging
import os


class JsonFormatter(logging.Formatter):
    """Format log records as JSON for CloudWatch Logs Insights."""

    def format(self, record):
        entry = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if hasattr(record, "request_id"):
            entry["request_id"] = record.request_id
        for key in ("course_id", "hole_num", "method", "path"):
            if hasattr(record, key):
                entry[key] = getattr(record, key)
        if record.exc_info and record.exc_info[0]:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


_configured = False


def get_logger(name):
    """Return a named logger with JSON formatting for CloudWatch."""
    global _configured
    if not _configured:
        root = logging.getLogger()
        root.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
        if root.handlers:
            root.handlers[0].setFormatter(JsonFormatter())
        _configured = True
    return logging.getLogger(name)
