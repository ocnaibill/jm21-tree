// Ghidra script: decompila funcoes para arquivos .c
// Uso: -postScript DecompileToFile.java <dir_saida> [filtro_no_nome]
// @category Lab

import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import java.io.File;
import java.io.PrintWriter;

public class DecompileToFile extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String outDir = args.length > 0 ? args[0] : "/tmp/ghidra-out";
        String filter = args.length > 1 ? args[1] : "";

        File dir = new File(outDir);
        if (!dir.exists() && !dir.mkdirs()) {
            println("nao foi possivel criar " + outDir);
            return;
        }

        DecompInterface ifc = new DecompInterface();
        ifc.toggleCCode(true);
        ifc.toggleSyntaxTree(true);
        if (!ifc.openProgram(currentProgram)) {
            println("falha ao abrir decompilador");
            return;
        }

        FunctionManager fm = currentProgram.getFunctionManager();
        int ok = 0, fail = 0, skipped = 0;
        for (Function f : fm.getFunctions(true)) {
            String name = f.getName();
            if (filter.isEmpty() == false && name.contains(filter) == false) {
                skipped++;
                continue;
            }
            if (f.isThunk()) {
                skipped++;
                continue;
            }
            try {
                DecompileResults res = ifc.decompileFunction(f, 90, monitor);
                if (!res.decompileCompleted()) {
                    fail++;
                    continue;
                }
                String c = res.getDecompiledFunction().getC();
                String safe = name.replace('/', '_').replace(' ', '_');
                File out = new File(dir, safe + ".c");
                try (PrintWriter pw = new PrintWriter(out, "UTF-8")) {
                    pw.println("// " + f.getEntryPoint() + "  " + f.getPrototypeString(false, false));
                    pw.println(c);
                }
                ok++;
            } catch (Exception e) {
                fail++;
            }
        }
        println("decompiladas=" + ok + " falhas=" + fail + " ignoradas=" + skipped);
        ifc.dispose();
    }
}
