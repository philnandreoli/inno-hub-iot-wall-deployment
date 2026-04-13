import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.schemas.chat import ChatRequest, ChatResponse
from app.services.openai_service import OpenAIChatService, get_openai_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["chat"])


@router.post("/chat", response_model=ChatResponse)
async def chat(
    payload: ChatRequest,
    service: OpenAIChatService = Depends(get_openai_service),
) -> ChatResponse:
    try:
        reply, conversation_id = await service.chat(
            message=payload.message,
            device_id=payload.device_id,
            conversation_id=payload.conversation_id,
        )
        return ChatResponse(
            reply=reply,
            conversation_id=conversation_id,
            device_id=payload.device_id,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.exception("Failed to process chat request")
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to process chat request",
        ) from exc
