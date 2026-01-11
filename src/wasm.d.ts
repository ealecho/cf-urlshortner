declare module '*.wasm' {
  const wasmModule: WebAssembly.Module;
  export default wasmModule;
}

declare namespace WebAssembly {
  class Suspending {
    constructor(fn: (...args: any[]) => Promise<any>);
  }
  function promising(fn: (...args: any[]) => any): (...args: any[]) => Promise<any>;
}

interface Env {
  URL_CACHE: KVNamespace;
  URL_DB: D1Database;
}
