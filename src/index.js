import express from "express";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const app = express();
const currentDir = dirname(fileURLToPath(import.meta.url));
const scriptsDir = join(currentDir, "..", "scripts");
const cacheHeader =
  "public, max-age=300, s-maxage=300, stale-while-revalidate=86400";

const scriptRoutes = {
  "/install.sh": {
    file: "install.sh",
    type: "text/x-shellscript; charset=utf-8",
  },
  "/install.ps1": {
    file: "install.ps1",
    type: "text/plain; charset=utf-8",
  },
  "/uninstall.sh": {
    file: "uninstall.sh",
    type: "text/x-shellscript; charset=utf-8",
  },
  "/uninstall.ps1": {
    file: "uninstall.ps1",
    type: "text/plain; charset=utf-8",
  },
};

for (const [route, script] of Object.entries(scriptRoutes)) {
  app.get(route, async (_request, response, next) => {
    try {
      const body = await readFile(join(scriptsDir, script.file), "utf8");
      response
        .status(200)
        .set("Cache-Control", cacheHeader)
        .type(script.type)
        .send(body);
    } catch (error) {
      next(error);
    }
  });
}

app.get("/healthz", (_request, response) => {
  response
    .status(200)
    .set("Cache-Control", "no-store")
    .type("application/json")
    .send({ ok: true });
});

app.use((_request, response) => {
  response.status(404).type("text/plain; charset=utf-8").send("not found\n");
});

app.use((error, _request, response, _next) => {
  console.error(error);
  response
    .status(500)
    .set("Cache-Control", "no-store")
    .type("text/plain; charset=utf-8")
    .send("internal server error\n");
});

if (!process.env.VERCEL && process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 3000);
  app.listen(port, () => {
    console.log(`get.rpath.dev listening on http://localhost:${port}`);
  });
}

export default app;
