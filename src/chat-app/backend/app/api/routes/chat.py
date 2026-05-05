import logging
from typing import Any, Annotated

from fastapi import APIRouter, Depends, HTTPException

from app.dependencies import get_chat_service, verify_token
from app.models.responses import ChatConfirmRequest, ChatRequest, ChatResponse
from app.services.chat_service import ChatService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/chat", tags=["chat"])

ClaimsDep = Annotated[dict[str, Any], Depends(verify_token)]
ChatServiceDep = Annotated[ChatService, Depends(get_chat_service)]


@router.post("", response_model=ChatResponse)
def chat(
    body: ChatRequest,
    service: ChatServiceDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    """Send a natural-language message and get an AI response.

    Read queries (status / telemetry) execute immediately.  Write commands
    (lamp / fan / blink) return a ``pendingAction`` that requires a follow-up
    call to ``POST /api/chat/confirm`` before the MQTT command is published.
    """
    try:
        result = service.chat(
            session_id=body.sessionId,
            user_message=body.message,
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("Chat processing failed for session %s", body.sessionId)
        raise HTTPException(status_code=502, detail="Chat processing failed") from exc

    pending = result.get("pending_action")
    return {
        "message": result["message"],
        "pendingAction": (
            {
                "functionName": pending["function_name"],
                "arguments": pending["arguments"],
                "description": pending["description"],
            }
            if pending
            else None
        ),
    }


@router.post("/confirm", response_model=ChatResponse)
def confirm_action(
    body: ChatConfirmRequest,
    service: ChatServiceDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    """Confirm and execute the pending write command for the given session."""
    try:
        result = service.confirm_action(session_id=body.sessionId)
    except Exception as exc:  # noqa: BLE001
        logger.exception(
            "Failed to confirm action for session %s", body.sessionId
        )
        raise HTTPException(
            status_code=502, detail="Failed to execute confirmed command"
        ) from exc

    pending = result.get("pending_action")
    return {
        "message": result["message"],
        "pendingAction": (
            {
                "functionName": pending["function_name"],
                "arguments": pending["arguments"],
                "description": pending["description"],
            }
            if pending
            else None
        ),
    }


@router.post("/cancel", response_model=ChatResponse)
def cancel_action(
    body: ChatConfirmRequest,
    service: ChatServiceDep,
    _claims: ClaimsDep,
) -> dict[str, Any]:
    """Cancel the pending write command for the given session."""
    try:
        result = service.cancel_action(session_id=body.sessionId)
    except Exception as exc:  # noqa: BLE001
        logger.exception(
            "Failed to cancel action for session %s", body.sessionId
        )
        raise HTTPException(
            status_code=502, detail="Failed to cancel command"
        ) from exc

    pending = result.get("pending_action")
    return {
        "message": result["message"],
        "pendingAction": (
            {
                "functionName": pending["function_name"],
                "arguments": pending["arguments"],
                "description": pending["description"],
            }
            if pending
            else None
        ),
    }
