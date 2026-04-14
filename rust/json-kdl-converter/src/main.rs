use std::fmt::Write as FmtWrite;
use std::fs;
use std::io::{self, Write};

use clap::{Parser, Subcommand};
use serde_json::{Map, Value};

#[derive(Parser)]
#[command(
    name = "json-kdl-converter",
    about = "Bidirectional JSON <-> KDL converter producing idiomatic, human-readable output"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Convert JSON to KDL
    Json2kdl {
        /// Input JSON file
        input: String,
        /// Output KDL file (stdout if omitted)
        output: Option<String>,
    },
    /// Convert KDL to JSON
    Kdl2json {
        /// Input KDL file
        input: String,
        /// Output JSON file (stdout if omitted)
        output: Option<String>,
    },
    /// Assemble split KDL settings into a single JSON file.
    /// Reads installation-steps.kdl and settings/*.kdl from the
    /// given directory, assembles them, and outputs JSON.
    Kdlset2json {
        /// Directory containing installation-steps.kdl and settings/
        dir: String,
        /// Output JSON file (stdout if omitted)
        output: Option<String>,
    },
}

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Commands::Json2kdl { input, output } => {
            let json_str = fs::read_to_string(&input).expect("Cannot read input file");
            // Strip JSONC single-line comments before parsing
            let clean: String = strip_jsonc_comments(&json_str);
            let value: Value = serde_json::from_str(&clean).expect("Invalid JSON");
            let mut buf = String::new();
            json_value_to_kdl_document(&value, &mut buf, 0);
            write_output(&buf, output.as_deref());
        }
        Commands::Kdl2json { input, output } => {
            let kdl_str = fs::read_to_string(&input).expect("Cannot read input file");
            let doc: kdl::KdlDocument = kdl_str.parse().expect("Invalid KDL");
            let value = kdl_document_to_json(&doc);
            let json =
                serde_json::to_string_pretty(&value).expect("JSON serialization failed");
            write_output(&json, output.as_deref());
        }
        Commands::Kdlset2json { dir, output } => {
            let json = assemble_kdlset(&dir);
            write_output(&json, output.as_deref());
        }
    }
}

// ---------------------------------------------------------------------------
// JSON -> KDL
// ---------------------------------------------------------------------------

/// Convert a top-level JSON value (expected to be an object) into a KDL document string.
fn json_value_to_kdl_document(value: &Value, buf: &mut String, depth: usize) {
    match value {
        Value::Object(map) => {
            for (key, val) in map {
                json_pair_to_kdl(key, val, buf, depth);
            }
        }
        _ => {
            // Top-level non-object: wrap in a single node
            let _ = write!(buf, "- ");
            write_kdl_value(val_ref(value), buf);
            buf.push('\n');
        }
    }
}

/// Write a single key-value pair as a KDL node.
fn json_pair_to_kdl(key: &str, value: &Value, buf: &mut String, depth: usize) {
    let indent = "    ".repeat(depth);

    match value {
        Value::Null => {
            let _ = writeln!(buf, "{indent}{} #null", format_node_name(key));
        }
        Value::Bool(b) => {
            let _ = writeln!(buf, "{indent}{} #{b}", format_node_name(key));
        }
        Value::Number(n) => {
            let _ = writeln!(buf, "{indent}{} {n}", format_node_name(key));
        }
        Value::String(s) => {
            let _ = write!(buf, "{indent}{} ", format_node_name(key));
            write_kdl_string(s, buf);
            buf.push('\n');
        }
        Value::Array(arr) => {
            if arr.is_empty() {
                // Skip empty arrays entirely — the consuming code should
                // treat a missing key as an empty array (which Raku's
                // Setting class already does via default values).
                return;
            } else if arr.iter().all(|v| is_primitive(v)) {
                // Array of primitives: all as arguments on one node
                let _ = write!(buf, "{indent}{}", format_node_name(key));
                for item in arr {
                    buf.push(' ');
                    write_kdl_value(item, buf);
                }
                buf.push('\n');
            } else {
                // Array with complex elements: use "-" child nodes
                let _ = writeln!(buf, "{indent}{} {{", format_node_name(key));
                for item in arr {
                    write_array_element(item, buf, depth + 1);
                }
                let _ = writeln!(buf, "{indent}}}");
            }
        }
        Value::Object(map) => {
            if map.is_empty() {
                return;
            }
            let _ = writeln!(buf, "{indent}{} {{", format_node_name(key));
            for (k, v) in map {
                json_pair_to_kdl(k, v, buf, depth + 1);
            }
            let _ = writeln!(buf, "{indent}}}");
        }
    }
}

/// Write a single array element as a "-" node.
fn write_array_element(value: &Value, buf: &mut String, depth: usize) {
    let indent = "    ".repeat(depth);

    match value {
        Value::Object(map) => {
            // Separate scalar values (-> properties) from non-scalars (-> children)
            let mut props: Vec<(&str, &Value)> = Vec::new();
            let mut children: Vec<(&str, &Value)> = Vec::new();

            for (k, v) in map {
                if is_primitive(v) {
                    props.push((k, v));
                } else {
                    children.push((k, v));
                }
            }

            if children.is_empty() {
                // All scalar: compact single-line form
                let _ = write!(buf, "{indent}-");
                for (k, v) in &props {
                    let _ = write!(buf, " {}=", format_node_name(k));
                    write_kdl_value(v, buf);
                }
                buf.push('\n');
            } else {
                // Has children: block form
                let _ = write!(buf, "{indent}-");
                for (k, v) in &props {
                    let _ = write!(buf, " {}=", format_node_name(k));
                    write_kdl_value(v, buf);
                }
                let _ = writeln!(buf, " {{");
                for (k, v) in &children {
                    json_pair_to_kdl(k, v, buf, depth + 1);
                }
                let _ = writeln!(buf, "{indent}}}");
            }
        }
        _ => {
            let _ = write!(buf, "{indent}- ");
            write_kdl_value(value, buf);
            buf.push('\n');
        }
    }
}

fn is_primitive(v: &Value) -> bool {
    matches!(v, Value::Null | Value::Bool(_) | Value::Number(_) | Value::String(_))
}

fn val_ref(v: &Value) -> &Value {
    v
}

/// Format a node name, quoting if necessary.
fn format_node_name(name: &str) -> String {
    // KDL v2: bare identifiers can contain letters, digits, and many symbols,
    // but not whitespace, and must not start with a digit.
    // For safety, quote anything that contains unusual characters.
    let needs_quoting = name.is_empty()
        || name.starts_with(|c: char| c.is_ascii_digit())
        || name.contains(|c: char| c.is_whitespace() || "{}()\\;=\"#".contains(c));

    if needs_quoting {
        format!("\"{}\"", name.replace('\\', "\\\\").replace('"', "\\\""))
    } else {
        name.to_string()
    }
}

/// Write a JSON value as a KDL value (inline, no trailing newline).
fn write_kdl_value(value: &Value, buf: &mut String) {
    match value {
        Value::Null => buf.push_str("#null"),
        Value::Bool(b) => {
            let _ = write!(buf, "#{b}");
        }
        Value::Number(n) => {
            let _ = write!(buf, "{n}");
        }
        Value::String(s) => write_kdl_string(s, buf),
        Value::Array(arr) => {
            // Inline array as multiple values — shouldn't normally be called
            for (i, item) in arr.iter().enumerate() {
                if i > 0 {
                    buf.push(' ');
                }
                write_kdl_value(item, buf);
            }
        }
        Value::Object(_) => {
            // Fallback: inline as JSON string
            let json = serde_json::to_string(value).unwrap_or_default();
            write_kdl_string(&json, buf);
        }
    }
}

/// Write a string with appropriate KDL quoting.
/// Uses raw strings (#"..."#) for strings containing backslashes or quotes.
fn write_kdl_string(s: &str, buf: &mut String) {
    let has_backslash = s.contains('\\');
    let has_newline = s.contains('\n');
    let has_quote = s.contains('"');

    if has_newline && (has_backslash || has_quote) {
        // Raw multiline string: #"""..."""#
        buf.push_str("#\"\"\"\n");
        buf.push_str(s);
        buf.push_str("\n\"\"\"#");
    } else if has_newline {
        // Regular multiline string
        buf.push_str("\"\"\"\n");
        buf.push_str(s);
        buf.push_str("\n\"\"\"");
    } else if has_backslash || has_quote {
        // Raw string: #"..."#
        buf.push_str("#\"");
        buf.push_str(s);
        buf.push_str("\"#");
    } else {
        buf.push('"');
        buf.push_str(s);
        buf.push('"');
    }
}

// ---------------------------------------------------------------------------
// KDL -> JSON
// ---------------------------------------------------------------------------

/// Convert a KDL document to a JSON value.
fn kdl_document_to_json(doc: &kdl::KdlDocument) -> Value {
    let nodes = doc.nodes();
    if nodes.is_empty() {
        return Value::Object(Map::new());
    }

    // Check if all nodes are named "-": this indicates an array
    if nodes.iter().all(|n| n.name().value() == "-") {
        return Value::Array(nodes.iter().map(kdl_node_to_json_value).collect());
    }

    // Check for duplicate names: if any name appears more than once, collect
    // into arrays.
    let mut counts: std::collections::HashMap<&str, usize> = std::collections::HashMap::new();
    for node in nodes {
        *counts.entry(node.name().value()).or_insert(0) += 1;
    }

    let mut map = Map::new();
    let mut arrays: std::collections::HashMap<String, Vec<Value>> =
        std::collections::HashMap::new();

    for node in nodes {
        let name = node.name().value().to_string();
        if counts[name.as_str()] > 1 {
            arrays
                .entry(name)
                .or_default()
                .push(kdl_node_to_json_value(node));
        } else {
            map.insert(name, kdl_node_to_json_value(node));
        }
    }

    for (name, arr) in arrays {
        map.insert(name, Value::Array(arr));
    }

    Value::Object(map)
}

/// Convert a single KDL node to a JSON value.
fn kdl_node_to_json_value(node: &kdl::KdlNode) -> Value {
    let entries = node.entries();
    let children = node.children();

    let args: Vec<&kdl::KdlEntry> = entries.iter().filter(|e| e.name().is_none()).collect();
    let props: Vec<&kdl::KdlEntry> = entries.iter().filter(|e| e.name().is_some()).collect();

    let has_children = children.map_or(false, |c| !c.nodes().is_empty());
    let has_args = !args.is_empty();
    let has_props = !props.is_empty();

    // Case 1: Node with only arguments, no props, no children
    // -> always an array (single-element arrays are preserved this way)
    if has_args && !has_props && !has_children {
        return Value::Array(args.iter().map(|a| kdl_entry_value_to_json(a.value())).collect());
    }

    // Case 2: Node with props and/or children -> object
    if has_props || has_children {
        let mut map = Map::new();

        // Add properties as scalar values
        for prop in &props {
            if let Some(name) = prop.name() {
                map.insert(
                    name.value().to_string(),
                    kdl_entry_value_to_json(prop.value()),
                );
            }
        }

        // Add children
        if let Some(children_doc) = children {
            let child_nodes = children_doc.nodes();

            // Check if all children are "-": array mode
            if !child_nodes.is_empty()
                && child_nodes.iter().all(|n| n.name().value() == "-")
            {
                if !has_props && !has_args {
                    return Value::Array(
                        child_nodes.iter().map(kdl_node_to_json_value).collect(),
                    );
                }
            }

            // Merge child nodes into the map
            let child_json = kdl_document_to_json(children_doc);
            if let Value::Object(child_map) = child_json {
                for (k, v) in child_map {
                    map.insert(k, v);
                }
            }
        }

        return Value::Object(map);
    }

    // Case 3: No args, no props, no children -> null
    Value::Null
}

fn kdl_entry_value_to_json(value: &kdl::KdlValue) -> Value {
    match value {
        kdl::KdlValue::String(s) => Value::String(s.clone()),
        kdl::KdlValue::Integer(i) => {
            // i128 -> try i64 first for serde_json compatibility
            if let Ok(n) = i64::try_from(*i) {
                Value::Number(n.into())
            } else {
                // Fallback: store as string for very large integers
                Value::String(i.to_string())
            }
        }
        kdl::KdlValue::Float(f) => {
            serde_json::Number::from_f64(*f)
                .map(Value::Number)
                .unwrap_or(Value::Null)
        }
        kdl::KdlValue::Bool(b) => Value::Bool(*b),
        kdl::KdlValue::Null => Value::Null,
    }
}

// ---------------------------------------------------------------------------
// JSONC comment stripping
// ---------------------------------------------------------------------------

fn strip_jsonc_comments(input: &str) -> String {
    let mut result = String::with_capacity(input.len());
    let mut in_string = false;
    let mut escape = false;
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        if escape {
            result.push(chars[i]);
            escape = false;
            i += 1;
            continue;
        }

        if in_string {
            if chars[i] == '\\' {
                escape = true;
                result.push(chars[i]);
            } else if chars[i] == '"' {
                in_string = false;
                result.push(chars[i]);
            } else {
                result.push(chars[i]);
            }
            i += 1;
            continue;
        }

        if chars[i] == '"' {
            in_string = true;
            result.push(chars[i]);
            i += 1;
        } else if chars[i] == '/' && i + 1 < chars.len() && chars[i + 1] == '/' {
            // Skip until end of line
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
        } else {
            result.push(chars[i]);
            i += 1;
        }
    }

    result
}

// ---------------------------------------------------------------------------
// Assemble split KDL settings
// ---------------------------------------------------------------------------

/// Read installation-steps.kdl and settings/*.kdl from `dir`,
/// assemble into a single KDL document, convert to JSON.
fn assemble_kdlset(dir: &str) -> String {
    let base = std::path::Path::new(dir);

    // Read installation-steps.kdl
    let steps_path = base.join("installation-steps.kdl");
    let steps_content = fs::read_to_string(&steps_path).unwrap_or_else(|e| {
        panic!("Cannot read {}: {e}", steps_path.display());
    });

    // Read all .kdl files from settings/ directory (recursively)
    let settings_dir = base.join("settings");
    let mut settings_content = String::new();

    if settings_dir.is_dir() {
        let mut kdl_files = Vec::new();
        collect_kdl_files(&settings_dir, &mut kdl_files);
        kdl_files.sort();

        for path in kdl_files {
            let content = fs::read_to_string(&path).unwrap_or_else(|e| {
                panic!("Cannot read {}: {e}", path.display());
            });
            settings_content.push_str(&content);
            settings_content.push('\n');
        }
    }

    // Assemble into a single KDL document
    let assembled = format!(
        "installation-steps {{\n{steps_content}\n}}\nsettings {{\n{settings_content}\n}}\n"
    );

    // Parse and convert to JSON
    let doc: kdl::KdlDocument = assembled.parse().unwrap_or_else(|e| {
        panic!("KDL parse error in assembled document: {e}");
    });
    let value = kdl_document_to_json(&doc);
    serde_json::to_string_pretty(&value).expect("JSON serialization failed")
}

/// Recursively collect all .kdl files from a directory.
/// Paths are sorted lexicographically, with directories traversed in order.
fn collect_kdl_files(dir: &std::path::Path, result: &mut Vec<std::path::PathBuf>) {
    let mut entries: Vec<_> = fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("Cannot read {}: {e}", dir.display()))
        .filter_map(|e| e.ok())
        .collect();
    entries.sort_by_key(|e| e.file_name());

    for entry in entries {
        let path = entry.path();
        if path.is_dir() {
            collect_kdl_files(&path, result);
        } else if path.extension().map_or(false, |ext| ext == "kdl") {
            result.push(path);
        }
    }
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

fn write_output(content: &str, path: Option<&str>) {
    match path {
        Some(p) => {
            fs::write(p, content).expect("Cannot write output file");
            eprintln!("Written to {p}");
        }
        None => {
            io::stdout()
                .write_all(content.as_bytes())
                .expect("Cannot write to stdout");
        }
    }
}