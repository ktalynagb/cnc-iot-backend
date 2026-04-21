from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from contextlib import asynccontextmanager

from app.database import engine, Base
from app.models.lectura import Lectura  # noqa: F401 — necesario para registrar tabla
from app.routers import datos, alertas
from app.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Crea las tablas si no existen al arrancar
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="CNC IoT Backend",
    description="API para monitoreo de vibración y temperatura en máquina CNC",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS abierto para que el dashboard de David pueda consultar
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(datos.router)
app.include_router(alertas.router)


@app.get("/", tags=["Health"])
def health_check():
    return {"status": "ok", "mensaje": "CNC IoT Backend corriendo 🏭"}
