package name.rafaismy.retrotoolbox;

interface IShellService {
    // Reserved by Shizuku: called when the service is unbound for good.
    void destroy() = 16777114;

    // Runs argv without a shell; returns {"code", "out", "err"} as JSON.
    String exec(in String[] argv) = 1;
}
