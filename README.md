# docker-postgres-backingup
Ejemplo de PostgreSQL con Docker haciendo copias de seguridad incrementales (Continuous Archiving, Point In Time Recovery (PITR))

Enlaces de interés:

- [Documentación de PostgreSQL: Continuous Archiving and Point-in-Time Recovery (PITR)](https://www.postgresql.org/docs/current/continuous-archiving.html)
- [Documentación de PostgreSQL: Configuración Write Ahead Log](https://www.postgresql.org/docs/current/runtime-config-wal.html)
- Herramientas de backup y restauración:
  [barman](https://www.pgbarman.org/),
  [wal-e](https://github.com/wal-e/wal-e),
  [wal-g](https://github.com/wal-g/wal-g),
  [pg_backrest](https://pgbackrest.org/),
  [pg_probackup](https://github.com/postgrespro/pg_probackup)
- [Tutorial de scalingpostgres.com](https://www.scalingpostgres.com/tutorials/postgresql-backup-point-in-time-recovery/) (Ojo, con la versión 10. Algunas cosas cambian)
- [Info: reemplazo del fichero recovery.conf por recovery.signal en la v12](https://www.cybertec-postgresql.com/en/recovery-conf-is-gone-in-postgresql-v12/)

## 1. Configurar parámetros

- [`archive_mode = on`](https://postgresqlco.nf/en/doc/param/archive_mode/)
- [`wal_level = replica`](https://postgresqlco.nf/en/doc/param/wal_level/)
- [`archive_command = 'arch-command %f %p'`](https://postgresqlco.nf/en/doc/param/archive_command/)
- [`restore_command = 'rest-command %f %p'`](https://postgresqlco.nf/en/doc/param/restore_command/)

Podemos hacerlo a través de la sentencia `ALTER SYSTEM`, que guarda los cambios en `postgres.auto.conf`, en vez de editar el fichero `postgres.conf`.  
Copiando este script en el directorio `/docker-entrypoint-initdb.d/` se ejecutará la primera vez que se inicie el contenedor.

```SQL
/* Habilita el archivado */
ALTER SYSTEM SET archive_mode = on;
/* Nivel de información de los ficheros WAL. Necesitaremos replica o logical */
ALTER SYSTEM SET wal_level = replica;
-- Podríamos crear e indicar scripts más refinados para los comandos
-- %f se sustituirá por el nombre del fichero y %p por la ruta del mismo
/* Cada vez que se completa un fichero WAL (16 MB default) se ejecuta archive_command */
ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/backups/wal/%f && cp %p /var/lib/postgresql/backups/wal/%f';
/* Cuando la base de datos entre en modo de recuperación ejecutará restore_command */
ALTER SYSTEM SET restore_command = 'cp /var/lib/postgresql/backups/wal/%f %p';
```

## 2. Generar una copia base

Utilizamos [`pg_basebackup`](https://www.postgresql.org/docs/current/app-pgbasebackup.html) para copiar el contenido del directorio $PGDATA (`/var/lib/postgresql/data/`)  

> IMPORTANTE: Primero debemos ajustar los permisos de los directorios en los que guardaremos las copias base y los ficheros WAL. El usuario postgres debe tener acceso.

```bash
# Creamos y hacemos propietario a postgres de los directorios donde se guardarán las copias
mkdir /var/lib/postgresql/backups/wal/
mkdir /var/lib/postgresql/backups/base/
chown -R postgres:postgres /var/lib/postgresql/backups/
```

> Nota: Podemos crear copias base cada cierto tiempo y conseguir así restauraciones más ágiles

```bash
# Generamos una copia base
# Flags interesantes:
#   -z: comprime los tar
#   -v: verboso
#   -P: muestra el progreso
su - postgres
pg_basebackup -Ft -D /var/lib/postgresql/backups/base/
```

## 3. Añadir algunos datos a un database

```bash
psql -c "CREATE DATABASE dbtest;"
psql dbtest postgres -c "
CREATE TABLE tabla (
  id SERIAL,
  hora timestamp without time zone default now(),
  texto varchar(100)
);
"
psql dbtest postgres -c "
INSERT INTO tabla (texto) VALUES ('En un lugar de la mancha');
INSERT INTO tabla (texto) VALUES ('de cuyo nombre no quiero acordarme');
SELECT * FROM tabla;
"
# Forzamos el cambio de fichero wal en vez de esperar a que se llene el actual
psql -U postgres -c "select pg_switch_wal();"

psql dbtest postgres -c "
INSERT INTO tabla (texto) VALUES ('Country roads, take me home');
INSERT INTO tabla (texto) VALUES ('To the place I belong');
INSERT INTO tabla (texto) VALUES ('West Virginia, mountain mama');
INSERT INTO tabla (texto) VALUES ('Take me home, country roads');
SELECT * FROM tabla;
"
# Forzamos el cambio de fichero wal en vez de esperar a que se llene el actual
psql -U postgres -c "select pg_switch_wal();"

psql dbtest postgres -c "
INSERT INTO tabla (texto) VALUES ('Dale a tu cuerpo alegria Macarena');
INSERT INTO tabla (texto) VALUES ('que tu cuerpo es para darle alegria y cosa buena');
INSERT INTO tabla (texto) VALUES ('eeeh Macarena.... aaahe');
SELECT * FROM tabla;
"
# Esta vez no forzamos el cambio del fichero wal. A ver qué pasa
```

## 4. Rompemos un poco las cosas

Podemos simular un fallo grave del sistema borrando ficheros de postgres:

```bash
# Podemos borrar algunos directorios y salir del contenedor
rm -rf /var/lib/postgresql/data/global /var/lib/postgresql/data/base
# O podemos borrar todo el directorio y automáticamente se detendrá el contenedor
# Allá vamos
rm -rf /var/lib/postgresql/data/*
```

Ahora pasamos a ejecutar los comandos desde nuestra máquina

## 5. Restauración

Debemos restaurar la copia base y hacer que postgres entre en modo recuperación

> NOTA: Especificar correctamente el path de los volúmenes

```bash
# Desde nuestra máquina restauramos el directorio $PGDATA con la copia base que tengamos
tar xvf path-volumen_backups/_data/base/base.tar -C path-volumen_data/_data/
tar xvf path-volumen_backups/_data/base/pg_wal.tar -C path-volumen_data/_data/pg_wal/
# Para que se inicie en modo de recuperación creamos el fichero recovery.signal
# Solo importa su presencia en $PGDATA, desapareciendo al finalizar la restauración
touch path-volumen_data/_data/recovery.signal
```

Si queremos realizar la recuperación hasta cierto punto del tiempo (PITR) debemos indicar ese momento en `postgres.conf` o `postgres.auto.conf`

- [`recovery_target_time = 'fecha hora'`](https://www.postgresql.org/docs/current/runtime-config-wal.html#GUC-RECOVERY-TARGET)

Ahora arrancamos el contenedor y se terminará la restauración a partir de los ficheros WAL.

Podemos comprobar que se restauró correctamente

```bash
psql dbtest postgres -c "select * from tabla;"
```

> Nota: Si restauramos con una marca de tiempo deberemos volver a habilitar manualmente el archivado:

```bash
psql -U postgres -c "select pg_wal_replay_resume();"
```
