from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import datos, alertas


app = FastAPI(
    title="CNC IoT Backend",
    description="API para monitoreo de vibración y temperatura en máquina CNC · Entrega 2",
    version="2.0.0",
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
