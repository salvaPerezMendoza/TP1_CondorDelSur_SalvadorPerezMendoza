# Cóndor del Sur
 
TP1 de Taller de Programación. Sistema CLI en Elixir que simula la reserva
concurrente de asientos de un vuelo.
 
Proyecto creado con `mix new condor_del_sur --no-sup`. 
 
---
 
## Cómo correrlo
 
```bash
mix compile                                     # compilar
mix run -e "CondorDelSur.Demo.run()"            # demo automática (TP)
mix run -e "CondorDelSur.CLI.main([])"          # CLI interactiva
mix test                                        # tests
```
 
La demo cubre los seis escenarios del enunciado: 6 pasajeros peleando por
el mismo asiento (gana 1), confirmación por pago, pago rechazado,
cancelación antes de pagar, expiración por TTL, y volcado del log. Usa
TTL de 4 s en lugar de 30 s para no demorar la salida.

Tambien se puede interactuar 
 
---
 
## Procesos del sistema
 
**Dos procesos con estado** (loop recursivo manual sobre `receive`):
 
| Proceso        | Registro       | Responsabilidad                                                          |
|----------------|----------------|--------------------------------------------------------------------------|
| `FlightServer` | `:flight_<ID>` | Único dueño del `%Flight{}`. Serializa todas las operaciones del vuelo.  |
| `AuditServer`  | `:audit`       | Log inmutable de eventos. Recibe del FlightServer en *fire-and-forget*.  |
 
**Dos tipos de procesos puntuales** (hacen su trabajo y mueren):
 
| Proceso   | Origen                                              | Qué hace                                            |
|-----------|-----------------------------------------------------|-----------------------------------------------------|
| `Payment` | `spawn` desde `FlightServer` al pedir pago          | Simula validación (sleep + 85% éxito) y reporta.    |
| `Expirer` | `spawn` desde `FlightServer` al iniciar una reserva | Duerme `ttl_ms` y manda `:check_expire` al server.  |
 
Cada **pasajero** corre en su propio proceso. La demo lanza 6 procesos
concurrentes para demostrar que solo uno gana el asiento.
 
---
 
## Estados
 
**Reserva**: `:pending` → `:confirmed` (pago OK) | `:cancelled` (usuario) |
`:expired` (TTL 30 s).
 
**Asiento**: `:available` ↔ `:reserved` ↔ `:confirmed`. Vuelve a
`:available` si la reserva se cancela o expira.
 
Una reserva ya cerrada (`confirmed`/`cancelled`/`expired`) es inmutable.
 
---
 
## Autor
 
Salvador Perez Mendoza 
110198
Taller de Programación, Cátedra Camejo, 2026.
