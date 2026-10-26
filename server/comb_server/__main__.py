"""Command line: `python -m comb_server <command>`.

  serve        run the server (default port 8080)
  setup-code   print a fresh one-time setup code (only before the first device)
  openapi      write the API contract to a file
"""
import argparse
import json
import logging
import sys
from pathlib import Path


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="comb_server", description="Comb sync server")
    sub = parser.add_subparsers(dest="command")

    serve = sub.add_parser("serve", help="Run the server")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8080)

    sub.add_parser("setup-code", help="Print a new one-time setup code")

    spec = sub.add_parser("openapi", help="Write the OpenAPI contract")
    spec.add_argument("path", nargs="?", default="-")

    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

    from .app import create_app, issue_setup_code
    from .config import load_settings

    if args.command in (None, "serve"):
        import uvicorn

        host = getattr(args, "host", "127.0.0.1")
        port = getattr(args, "port", 8080)
        uvicorn.run(create_app(), host=host, port=port, proxy_headers=True)
        return 0

    if args.command == "setup-code":
        settings = load_settings()
        app = create_app(settings)
        code = issue_setup_code(settings, app.state.db)
        if code is None:
            print("This server already has an account. Add devices by pairing from an existing device.")
            return 1
        print(f"One-time setup code: {code}")
        return 0

    if args.command == "openapi":
        import tempfile
        from dataclasses import replace

        logging.disable(logging.WARNING)
        with tempfile.TemporaryDirectory() as scratch:
            app = create_app(replace(load_settings(), data_dir=Path(scratch)))
            text = json.dumps(app.openapi(), indent=2, sort_keys=True) + "\n"
            app.state.db.close()
        if args.path == "-":
            sys.stdout.write(text)
        else:
            Path(args.path).write_text(text, encoding="utf-8")
        return 0

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
