# Funcionalidad de Despliegue en Segundo Plano

## 🎯 Resumen de Cambios

Se ha añadido funcionalidad completa de **despliegue en segundo plano** al script `deploy-via-jumphost.sh`, permitiendo ejecutar despliegues largos sin bloquear la terminal.

## ✨ Nuevas Funcionalidades

### 1. **Despliegue en Segundo Plano** (`-b, --background`)
```bash
./deploy-via-jumphost.sh -b full
```
- Ejecuta el despliegue en segundo plano
- Devuelve el control inmediatamente
- Guarda información del proceso para monitoreo

### 2. **Seguimiento de Logs en Tiempo Real** (`--follow-logs`)
```bash
./deploy-via-jumphost.sh --follow-logs install-operators
```
- Ejecuta en segundo plano Y muestra logs en tiempo real
- Permite detener el seguimiento con Ctrl+C (el despliegue continúa)
- Útil para monitorear el progreso sin bloquear

### 3. **Estado de Despliegues** (`--status`)
```bash
./deploy-via-jumphost.sh --status
```
- Muestra todos los despliegues en segundo plano
- Indica estado: ejecutándose, terminado, detenido
- Muestra duración y archivos de log

### 4. **Detener Despliegues** (`--stop PID`)
```bash
./deploy-via-jumphost.sh --stop 12345
```
- Detiene un despliegue específico por PID
- Intenta terminación elegante primero (SIGTERM)
- Fuerza terminación si es necesario (SIGKILL)

## 🏗️ Arquitectura Técnica

### Gestión de Procesos
- **Directorio PID**: `pids/` - almacena información de procesos
- **Archivos de información**: `pids/[PID].info` con metadatos
- **Limpieza automática**: detecta procesos terminados

### Logging Mejorado
- **Logs persistentes**: todos los despliegues se registran
- **Timestamps**: seguimiento completo de duración
- **Identificación única**: cada despliegue tiene su log

### Estados de Proceso
- `running` - Ejecutándose activamente
- `finished` - Completado exitosamente
- `stopped` - Detenido manualmente

## 📋 Ejemplos de Uso

### Caso 1: Despliegue Largo sin Supervisión
```bash
# Iniciar despliegue completo en segundo plano
./deploy-via-jumphost.sh -b full

# Verificar progreso más tarde
./deploy-via-jumphost.sh --status

# Ver logs si es necesario
tail -f logs/deployment_lab123_20251001_143022.log
```

### Caso 2: Monitoreo Activo
```bash
# Ejecutar con seguimiento de logs
./deploy-via-jumphost.sh --follow-logs control-plane

# El despliegue continúa aunque presiones Ctrl+C
```

### Caso 3: Gestión de Múltiples Despliegues
```bash
# Iniciar varios despliegues
./deploy-via-jumphost.sh -b prerequisites
./deploy-via-jumphost.sh -b install-operators

# Verificar todos
./deploy-via-jumphost.sh --status

# Detener uno específico si es necesario
./deploy-via-jumphost.sh --stop 12345
```

## 🔧 Archivos Modificados

### `deploy-via-jumphost.sh`
- **Nuevas opciones**: `-b`, `--background`, `--follow-logs`, `--status`, `--stop`
- **Funciones añadidas**:
  - `save_background_process()` - Guarda información del proceso
  - `show_background_status()` - Muestra estado de procesos
  - `stop_background_deployment()` - Detiene procesos
  - `follow_deployment_logs()` - Sigue logs en tiempo real
  - `cleanup_old_pids()` - Limpia procesos terminados

### Nuevos Archivos
- `background_deployment_examples.sh` - Ejemplos de uso
- `BACKGROUND_DEPLOYMENT_SUMMARY.md` - Esta documentación

## 🚀 Beneficios

### Para Administradores
- **Despliegues no bloqueantes**: continúa trabajando mientras se despliega
- **Monitoreo flexible**: verifica estado cuando sea conveniente
- **Control granular**: detén despliegues específicos si es necesario

### Para Operaciones
- **Despliegues paralelos**: ejecuta múltiples labs simultáneamente
- **Logs persistentes**: historial completo de todas las operaciones
- **Recuperación**: reinicia desde donde se quedó

### Para Debugging
- **Logs detallados**: cada despliegue tiene su archivo de log
- **Información de proceso**: metadatos completos de cada ejecución
- **Estados claros**: sabe exactamente qué está pasando

## 🔄 Compatibilidad

- **100% compatible**: funcionalidad existente sin cambios
- **Modo por defecto**: sigue siendo ejecución en primer plano
- **Opciones adicionales**: solo se activan explícitamente

## 📊 Casos de Uso Recomendados

### ✅ Usar Segundo Plano Para:
- Despliegues completos (`full`)
- Fases largas (`control-plane`, `data-plane`)
- Múltiples labs simultáneos
- Despliegues nocturnos/automatizados

### ⚠️ Usar Primer Plano Para:
- Verificaciones rápidas (`-c`)
- Dry runs (`-d`)
- Debugging interactivo
- Fases cortas (`prerequisites`)

## 🛠️ Mantenimiento

### Limpieza Automática
- Los archivos PID se actualizan automáticamente
- Procesos terminados se marcan como `finished`
- No requiere intervención manual

### Monitoreo del Sistema
```bash
# Ver todos los procesos de despliegue
ps aux | grep deploy-via-jumphost

# Ver archivos de información
ls -la pids/

# Limpiar archivos antiguos (opcional)
find pids/ -name "*.info" -mtime +7 -delete
```

---

**Estado**: ✅ Implementación completa  
**Fecha**: Octubre 2025  
**Compatibilidad**: Totalmente compatible con versión anterior
