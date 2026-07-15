require "active_record/tasks/database_tasks"

# A SQL schema dump must also load into an already-created PostgreSQL database.
# `--clean --if-exists`, together with dump_schemas=:all, preserves PostGIS and
# removes existing objects before recreating them.
ActiveRecord::Tasks::DatabaseTasks.structure_dump_flags = {
  postgresql: %w[--clean --if-exists]
}
