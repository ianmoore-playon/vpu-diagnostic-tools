import { spawn } from "child_process";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPTS_DIR = join(__dirname, "scripts");

const IS_WINDOWS = process.platform === "win32";

/**
 * Run a PowerShell script and return parsed JSON output.
 *
 * @param {string} scriptName  - Filename inside server/scripts/ (e.g. "Get-Performance.ps1")
 * @param {Record<string, string|number|boolean>} args - Key/value pairs become -Key Value params
 * @param {{ timeout?: number }} options
 * @returns {Promise<object>}
 */
export function runScript(scriptName, args = {}, { timeout = 30_000 } = {}) {
  // On non-Windows platforms return mock data so development works on macOS/Linux
  if (!IS_WINDOWS) {
    return Promise.resolve({
      _mock: true,
      _script: scriptName,
    });
  }

  return new Promise((resolve, reject) => {
    const scriptPath = join(SCRIPTS_DIR, scriptName);

    const psArgs = [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
    ];

    // Append -Key Value pairs from the args object
    for (const [key, value] of Object.entries(args)) {
      psArgs.push(`-${key}`);
      psArgs.push(String(value));
    }

    const child = spawn("powershell.exe", psArgs, {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`Script ${scriptName} timed out after ${timeout}ms`));
    }, timeout);

    child.on("error", (err) => {
      clearTimeout(timer);
      reject(new Error(`Failed to spawn powershell for ${scriptName}: ${err.message}`));
    });

    child.on("close", (code) => {
      clearTimeout(timer);

      if (code !== 0) {
        return reject(
          new Error(
            `Script ${scriptName} exited with code ${code}. stderr: ${stderr.trim()}`
          )
        );
      }

      const trimmed = stdout.trim();
      if (!trimmed) {
        return reject(new Error(`Script ${scriptName} produced no output`));
      }

      try {
        resolve(JSON.parse(trimmed));
      } catch (parseErr) {
        reject(
          new Error(
            `Script ${scriptName} returned invalid JSON: ${parseErr.message}. Output: ${trimmed.slice(0, 200)}`
          )
        );
      }
    });
  });
}
