from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Base de datos
    DB_HOST: str = "localhost"
    DB_PORT: int = 5432
    DB_NAME: str = "cnc_iot"
    DB_USER: str = "cnc_user"
    DB_PASSWORD: str = "password"

    # Servidor
    APP_HOST: str = "0.0.0.0"
    APP_PORT: int = 8000

    # CSV
    CSV_PATH: str = "data/lecturas.csv"

    # Umbrales de alerta
    TEMP_MIN: float = 15.0
    TEMP_MAX: float = 45.0
    ACCEL_MAX: float = 2.0

    class Config:
        env_file = ".env"


settings = Settings()
