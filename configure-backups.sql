-- Esta configuración se añadirá al fichero postgresql.auto.conf
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET wal_level = replica;
/* Comandos básicos: */
-- ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/backups/wal/%f && cp %p /var/lib/postgresql/backups/wal/%f';
-- ALTER SYSTEM SET restore_command = 'cp /var/lib/postgresql/backups/wal/%f %p';
/* Podríamos indicar scripts o usar alguna herramienta como barman*/
-- ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/backups/wal/%f && cp %p /var/lib/postgresql/backups/wal/%f && echo $(date) %f >> /var/lib/postgresql/backups/archiving.log';
ALTER SYSTEM SET archive_command = 'echo $(date +"%Y-%m-%d %T.%3N UTC") $(test ! -f /var/lib/postgresql/backups/wal/%f && (cp %p /var/lib/postgresql/backups/wal/%f && echo COPIED) || echo UNABLE TO COPY) file %f >> /var/lib/postgresql/backups/archiving.log'; 
-- ALTER SYSTEM SET restore_command = 'cp /var/lib/postgresql/backups/wal/%f %p && echo $(date) %f >> /var/lib/postgresql/backups/archiving.log';
ALTER SYSTEM SET restore_command = 'echo $(date +"%Y-%m-%d %T.%3N UTC") $(cp /var/lib/postgresql/backups/wal/%f %p && echo RESTORED || echo UNABLE TO RESTORE) file %f >> /var/lib/postgresql/backups/archiving.log';
