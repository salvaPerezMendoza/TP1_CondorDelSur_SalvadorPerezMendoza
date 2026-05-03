# Cóndor del Sur
 
TP1 de Taller de Programación. Sistema CLI en Elixir que simula la reserva
concurrente de asientos de un vuelo.
 
Proyecto creado con `mix new condor_del_sur --no-sup`. **No** usa
`GenServer`, `Supervisor`, `Task`, `Agent`, `Registry` ni ningún otro
behaviour de OTP. Toda la concurrencia se construye con `spawn/1`,
`send/2`, `receive`, `Process.register/2` y `Process.monitor/1`.
 
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
 
Comandos de la CLI: `summary`, `available`, `add_passenger <id> <name>`,
`reserve <pid> <seat>`, `pay <res_id>`, `cancel <res_id>`, `show <res_id>`,
`audit`, `quit`.
 
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
 
## `Process.register/2` y `Process.monitor/1`
 
- **`Process.register/2`** se usa en `FlightServer.start/2` (registro
  `:flight_<ID>`) y en `AuditServer.start/1` (registro `:audit`).
  Permite que el `Payment` y el `Expirer` le manden mensajes al server
  por nombre, sin tener que conocer el PID.
- **`Process.monitor/1`** se usa en `CLI.main/1`. La CLI vigila ambos
  servers; si alguno cae, recibe un `{:DOWN, ...}` y avisa al usuario
  sin terminar la sesión. Para probarlo: arrancá la CLI y desde otra
  terminal `iex -S mix` corré
  `Process.exit(Process.whereis(:audit), :kill)`.
---
 
## Estados
 
**Reserva**: `:pending` → `:confirmed` (pago OK) | `:cancelled` (usuario) |
`:expired` (TTL 30 s).
 
**Asiento**: `:available` ↔ `:reserved` ↔ `:confirmed`. Vuelve a
`:available` si la reserva se cancela o expira.
 
Una reserva ya cerrada (`confirmed`/`cancelled`/`expired`) es inmutable.
 
---
 
## Estructura
 
```
lib/condor_del_sur/
├── passenger.ex, seat.ex, reservation.ex   ← structs
├── flight.ex                               ← struct + lógica pura
├── flight_server.ex, audit_server.ex       ← procesos con estado
├── payment.ex                              ← tarea puntual
├── cli.ex                                  ← CLI + Process.monitor/1
└── demo.ex                                 ← demo del TP
test/
├── flight_test.exs                         ← lógica pura (6 casos del TP)
└── flight_server_test.exs                  ← protocolo + concurrencia (N=50)
```
 
---
 
## Decisiones de diseño
 
**Un proceso por vuelo** da consistencia sin locks (no hay memoria
compartida mutable), a costa de ser cuello de botella por vuelo. Es lo
adecuado para este TP.
 
**Pago y expiración como procesos puntuales** evitan que el `FlightServer`
se bloquee con sleeps y deje de atender pedidos, que es exactamente el
problema que el enunciado quiere evitar.
 
**`String.to_atom/1`** se usa para derivar el nombre `:flight_<ID>`. Es
seguro porque la cantidad de vuelos es finita y conocida; en producción
con miles de vuelos dinámicos habría que usar otra estrategia.
 
---
 
## Autor
 
Salvador Pérez Mendoza — Taller de Programación, Cátedra Camejo, 2026.