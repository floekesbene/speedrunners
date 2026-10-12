// Luau-Werkzeug:
//   luaucheck <dateien...>        kompiliert jede Datei (Syntaxprüfung)
//   luaucheck --run <datei> [args] führt ein Luau-Skript aus (Mock-Tests)
// Host-Funktionen für --run: __readfile(path), __compile(source, name, env), __args
use mlua::prelude::*;
use std::fs;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(|s| s.as_str()) == Some("--run") {
        let lua = Lua::new();
        let globals = lua.globals();
        let readfile = lua
            .create_function(|_, path: String| {
                fs::read_to_string(&path).map_err(|e| LuaError::RuntimeError(format!("{}: {}", path, e)))
            })
            .unwrap();
        globals.set("__readfile", readfile).unwrap();
        let compile = lua
            .create_function(|lua, (source, name, env): (String, String, LuaTable)| {
                let f = lua.load(&source).set_name(name).set_environment(env).into_function()?;
                Ok(f)
            })
            .unwrap();
        globals.set("__compile", compile).unwrap();
        let script_args = lua.create_table().unwrap();
        for (i, a) in args.iter().skip(2).enumerate() {
            script_args.set(i + 1, a.clone()).unwrap();
        }
        globals.set("__args", script_args).unwrap();
        let path = &args[1];
        let src = fs::read_to_string(path).expect("read");
        match lua.load(&src).set_name(path.as_str()).exec() {
            Ok(_) => println!("RUN OK: {}", path),
            Err(e) => {
                eprintln!("RUN FAIL: {}\n{}", path, e);
                std::process::exit(1);
            }
        }
        return;
    }
    let lua = Lua::new();
    let mut failed = 0;
    for path in &args {
        let src = fs::read_to_string(path).expect("read");
        match lua.load(&src).set_name(path.as_str()).into_function() {
            Ok(_) => {}
            Err(e) => {
                failed += 1;
                eprintln!("SYNTAX ERROR {}:\n{}\n", path, e);
            }
        }
    }
    println!("checked {} files, {} failed", args.len(), failed);
    if failed > 0 {
        std::process::exit(1);
    }
}
