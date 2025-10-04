# Guía de Múltiples Ejecuciones - deploy-via-jumphost.sh

## 🔄 **¿Es posible ejecutar el script múltiples veces?**

**SÍ**, pero depende del escenario. Esta guía te explica cuándo es seguro y cuándo debes tener cuidado.

## ✅ **Escenarios SEGUROS**

### 1. **Ejecuciones Secuenciales por Fases**
```bash
# ✅ RECOMENDADO: Una fase tras otra
./deploy-via-jumphost.sh prerequisites
# Esperar a que termine...

./deploy-via-jumphost.sh install-operators  
# Esperar a que termine...

./deploy-via-jumphost.sh control-plane
```

**Por qué es seguro:**
- Solo un proceso activo a la vez
- Cada fase construye sobre la anterior
- No hay conflictos de recursos

### 2. **Re-ejecución de Fases Fallidas**
```bash
./deploy-via-jumphost.sh install-operators
# Si falla...

./deploy-via-jumphost.sh install-operators  # ✅ Re-ejecutar
```

**Por qué es seguro:**
- Ansible es idempotente
- Solo aplica cambios necesarios
- No daña configuración existente

### 3. **Dry Runs Ilimitados**
```bash
./deploy-via-jumphost.sh -d full
./deploy-via-jumphost.sh -d control-plane
./deploy-via-jumphost.sh -d validation
# ✅ Todos seguros simultáneamente
```

**Por qué es seguro:**
- No hacen cambios reales
- Solo verifican configuración
- No afectan el entorno

### 4. **Verificaciones y Monitoreo**
```bash
./deploy-via-jumphost.sh -c          # ✅ Check inventory
./deploy-via-jumphost.sh --status    # ✅ Ver estado
./deploy-via-jumphost.sh --stop 1234 # ✅ Detener proceso
```

## ⚠️ **Escenarios PROBLEMÁTICOS**

### 1. **Múltiples Despliegues Completos Simultáneos**
```bash
# ❌ PROBLEMÁTICO
./deploy-via-jumphost.sh -b full     # PID 1234
./deploy-via-jumphost.sh -b full     # PID 5678 - CONFLICTO
```

**Problemas que causa:**
- Ambos intentan modificar los mismos recursos OpenShift
- Conflictos en archivos del bastion
- Estados inconsistentes
- Posibles fallos de despliegue

### 2. **Fases Conflictivas Simultáneas**
```bash
# ❌ PROBLEMÁTICO
./deploy-via-jumphost.sh -b install-operators &
./deploy-via-jumphost.sh -b install-operators   # Misma fase
```

### 3. **Mezclar Full con Fases Específicas**
```bash
# ❌ PROBLEMÁTICO  
./deploy-via-jumphost.sh -b full &              # Despliegue completo
./deploy-via-jumphost.sh control-plane          # Fase específica
```

## 🛡️ **Protecciones Implementadas**

### 1. **Detección Automática de Conflictos**
El script ahora detecta automáticamente conflictos potenciales:

```bash
./deploy-via-jumphost.sh -b full
# Si ya hay un despliegue corriendo:
# ⚠️  Potential deployment conflicts detected:
#    PID 1234: lab123 (full)
# Continue anyway? (y/N):
```

### 2. **Directorios Únicos**
Cada ejecución usa directorios temporales únicos:
```bash
/tmp/rhoso-deploy-1234  # PID 1234
/tmp/rhoso-deploy-5678  # PID 5678
```

### 3. **Logs Separados**
Cada ejecución genera su propio log:
```bash
logs/deployment_lab123_20251001_143022.log
logs/deployment_lab123_20251001_144015.log
```

### 4. **Gestión de PIDs**
Seguimiento individual de cada proceso:
```bash
pids/1234.info  # Información del proceso 1234
pids/5678.info  # Información del proceso 5678
```

## 🔧 **Mejores Prácticas**

### ✅ **Flujo Recomendado para Múltiples Ejecuciones**

#### Opción 1: Secuencial por Fases
```bash
# 1. Verificar estado
./deploy-via-jumphost.sh --status

# 2. Ejecutar fase por fase
./deploy-via-jumphost.sh prerequisites
./deploy-via-jumphost.sh install-operators
./deploy-via-jumphost.sh control-plane
./deploy-via-jumphost.sh data-plane
./deploy-via-jumphost.sh validation
```

#### Opción 2: Background con Monitoreo
```bash
# 1. Iniciar en segundo plano
./deploy-via-jumphost.sh -b full

# 2. Monitorear progreso
./deploy-via-jumphost.sh --status

# 3. Seguir logs si necesario
tail -f logs/deployment_*.log
```

#### Opción 3: Múltiples Labs (Diferentes)
```bash
# ✅ SEGURO: Labs diferentes
./deploy-via-jumphost.sh -b --inventory lab1/hosts.yml full &
./deploy-via-jumphost.sh -b --inventory lab2/hosts.yml full &
./deploy-via-jumphost.sh -b --inventory lab3/hosts.yml full &
```

### ⚠️ **Qué Hacer Si Hay Conflictos**

#### 1. **Verificar Estado Actual**
```bash
./deploy-via-jumphost.sh --status
```

#### 2. **Detener Procesos Conflictivos**
```bash
./deploy-via-jumphost.sh --stop 1234
```

#### 3. **Esperar a que Termine**
```bash
# Monitorear hasta que termine
while ./deploy-via-jumphost.sh --status | grep -q "running"; do
    sleep 30
done
```

#### 4. **Limpiar Estado si es Necesario**
```bash
# Solo si hay problemas graves
rm -rf pids/*.info
```

## 🚨 **Señales de Problemas**

### Síntomas de Conflictos:
- ❌ Errores de "resource already exists" en OpenShift
- ❌ Fallos de SSH al bastion
- ❌ Logs que se detienen inesperadamente
- ❌ Procesos zombie en `--status`

### Cómo Resolverlos:
1. **Detener todos los procesos**: `./deploy-via-jumphost.sh --stop PID`
2. **Verificar estado**: `./deploy-via-jumphost.sh --status`
3. **Limpiar si es necesario**: `rm -rf pids/*.info`
4. **Re-ejecutar uno a la vez**: `./deploy-via-jumphost.sh full`

## 📊 **Matriz de Compatibilidad**

| Escenario | Mismo Lab | Labs Diferentes | Seguridad |
|-----------|-----------|-----------------|-----------|
| Secuencial | ✅ Seguro | ✅ Seguro | Alta |
| Dry runs | ✅ Seguro | ✅ Seguro | Alta |
| Fases diferentes simultáneas | ⚠️ Cuidado | ✅ Seguro | Media |
| Misma fase simultánea | ❌ Evitar | ✅ Seguro | Baja |
| Full + específica | ❌ Evitar | ✅ Seguro | Baja |
| Múltiples full | ❌ Evitar | ✅ Seguro | Baja |

## 🎯 **Recomendaciones Finales**

### Para Uso Diario:
- **Usa ejecuciones secuenciales** para máxima seguridad
- **Monitorea con `--status`** antes de iniciar nuevos despliegues
- **Usa dry runs** para probar configuraciones

### Para Operaciones Avanzadas:
- **Labs diferentes** pueden ejecutarse simultáneamente
- **Background mode** para despliegues largos
- **Detén procesos** si detectas conflictos

### Para Debugging:
- **Logs únicos** para cada ejecución
- **PIDs rastreables** para control granular
- **Re-ejecución segura** de fases fallidas

---

**Resumen**: ✅ **SÍ es posible ejecutar múltiples veces**, pero sigue las mejores prácticas para evitar conflictos y asegurar despliegues exitosos.
