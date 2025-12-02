"""Configuration management for Agent Lightning service"""
import os
from typing import Optional
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables"""

    # Service Configuration
    api_host: str = "0.0.0.0"
    api_port: int = 4747
    store_host: str = "0.0.0.0"
    store_port: int = 4748

    # Database Configuration
    database_url: str = os.getenv(
        "DATABASE_URL",
        "postgresql://user:password@localhost:5432/agent_marketing_development"
    )

    # Rails API Configuration
    rails_api_url: str = os.getenv("RAILS_API_URL", "http://localhost:3000")
    rails_api_key: Optional[str] = os.getenv("RAILS_API_KEY")

    # Agent Lightning Configuration
    n_runners: int = int(os.getenv("AGENT_LIGHTNING_RUNNERS", "4"))
    execution_strategy: str = os.getenv("AGENT_LIGHTNING_STRATEGY", "cs")

    # Training Configuration
    default_learning_rate: float = 0.001
    default_batch_size: int = 32
    default_epochs: int = 3
    max_runners: int = 16

    # Logging
    log_level: str = os.getenv("LOG_LEVEL", "INFO")
    debug: bool = os.getenv("DEBUG", "false").lower() == "true"

    # Storage
    checkpoint_dir: str = "/app/checkpoints"
    temp_dir: str = "/tmp/agent_lightning"

    # Timeouts
    rollout_timeout_seconds: int = 600
    unresponsive_timeout_seconds: int = 120
    max_attempts: int = 3

    class Config:
        env_file = ".env"
        case_sensitive = False


# Global settings instance
settings = Settings()
