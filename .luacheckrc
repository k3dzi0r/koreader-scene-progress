-- Same baseline as KOReader's .luacheckrc; standalone test files are plain Lua.
std = "luajit"
unused_args = false
self = false
globals = { "G_reader_settings", "G_defaults", "table.pack", "table.unpack" }
ignore = { "211/__*", "231/__*", "631" }
