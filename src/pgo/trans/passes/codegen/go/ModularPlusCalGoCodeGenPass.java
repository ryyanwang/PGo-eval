package pgo.trans.passes.codegen.go;

import pgo.PGoOptions;
import pgo.model.golang.*;
import pgo.model.golang.builder.GoBlockBuilder;
import pgo.model.golang.builder.GoFunctionDeclarationBuilder;
import pgo.model.golang.builder.GoModuleBuilder;
import pgo.model.golang.type.GoSliceType;
import pgo.model.golang.type.GoType;
import pgo.model.golang.type.GoTypeName;
import pgo.model.mpcal.ModularPlusCalArchetype;
import pgo.model.mpcal.ModularPlusCalBlock;
import pgo.model.pcal.PlusCalStatement;
import pgo.model.pcal.PlusCalVariableDeclaration;
import pgo.model.tla.PlusCalDefaultInitValue;
import pgo.model.tla.TLAExpression;
import pgo.model.type.PGoType;
import pgo.model.type.PGoTypeMap;
import pgo.scope.UID;
import pgo.trans.intermediate.DefinitionRegistry;

import java.util.*;

public class ModularPlusCalGoCodeGenPass {
    private ModularPlusCalGoCodeGenPass() {}

    private static void generateLocalVariableDefinitions(DefinitionRegistry registry, Map<UID, PGoType> typeMap,
                                                         GlobalVariableStrategy globalStrategy, GoBlockBuilder processBody,
                                                         List<PlusCalVariableDeclaration> variableDeclarations) {
        for (PlusCalVariableDeclaration variableDeclaration : variableDeclarations) {
            GoVariableName name;

            if (variableDeclaration.getValue() instanceof PlusCalDefaultInitValue) {
                GoType varType = typeMap.get(variableDeclaration.getUID()).accept(new PGoTypeGoTypeConversionVisitor());
                name = processBody.varDecl(variableDeclaration.getName().getValue(), varType);
            } else {
                GoExpression value = variableDeclaration.getValue().accept(
                        new TLAExpressionCodeGenVisitor(processBody, registry, typeMap, globalStrategy));
                if (variableDeclaration.isSet()) {
                    value = new GoIndexExpression(value, new GoIntLiteral(0));
                }

                name = processBody.varDecl(variableDeclaration.getName().getValue(), value);
            }
            processBody.linkUID(variableDeclaration.getUID(), name);
        }
    }

    private static void generateInit(GoModuleBuilder module, DefinitionRegistry registry, Map<UID, PGoType> typeMap, GlobalVariableStrategy globalStrategy) {
        Map<String, PGoType> constants = new TreeMap<>(); // sort constants for deterministic compiler output
        Map<String, UID> constantIds = new HashMap<>();
        for (UID uid : registry.getConstants()) {
            String name = registry.getConstantName(uid);
            constants.put(name, typeMap.get(uid));
            constantIds.put(name, uid);
        }

        try (GoBlockBuilder initBuilder = module.defineFunction("init").getBlockBuilder()) {
            // generate constant definitions and initializations
            for (Map.Entry<String, PGoType> pair : constants.entrySet()) {
                TLAExpression value = registry.getConstantValue(constantIds.get(pair.getKey()));
                PGoType type = typeMap.get(constantIds.get(pair.getKey()));
                GoVariableName name = module.defineGlobal(
                        constantIds.get(pair.getKey()),
                        pair.getKey(),
                        type.accept(new PGoTypeGoTypeConversionVisitor()));
                initBuilder.assign(
                        name,
                        value.accept(new TLAExpressionCodeGenVisitor(initBuilder, registry, typeMap, globalStrategy)));
            }
        }
    }

    public static GoModule perform(DefinitionRegistry registry, Map<UID, PGoType> typeMap, PGoOptions opts,
                                   ModularPlusCalBlock modularPlusCalBlock) {
        GoModuleBuilder module = new GoModuleBuilder(modularPlusCalBlock.getName().getValue(), opts.buildPackage);
        GlobalVariableStrategy globalStrategy = new ArchetypeResourcesGlobalVariableStrategy(registry, typeMap);

        generateInit(module, registry, typeMap, globalStrategy);

        for (ModularPlusCalArchetype archetype : modularPlusCalBlock.getArchetypes()) {
            GoFunctionDeclarationBuilder fn = module.defineFunction(archetype.getUID(), archetype.getName());
            fn.addReturn(GoBuiltins.Error);

            Map<String, GoVariableName> argMap = new HashMap<>();

            // all archetypes have a `self` parameter
            GoVariableName selfVariable = fn.addParameter("self", GoBuiltins.Int);
            GoType resourceType = new GoTypeName("distsys.ArchetypeResource");

            for (PlusCalVariableDeclaration arg : archetype.getParams()) {
                module.addImport("pgo/distsys");

                // find out if archetype resource should be passed as a slice if it is used
                // like a TLA+ function in the archetype's body
                GoType argType = resourceType;
                if (typeMap.get(arg.getUID()) instanceof PGoTypeMap) {
                    argType = new GoSliceType(resourceType);
                }

                argMap.put(arg.getName().getValue(), fn.addParameter(arg.getName().getValue(), argType));
            }

            try (GoBlockBuilder fnBody = fn.getBlockBuilder()) {
                // link the 'self' parameter
                fnBody.linkUID(archetype.getSelfVariableUID(), selfVariable);

                for (PlusCalVariableDeclaration arg : archetype.getParams()) {
                    fnBody.linkUID(arg.getUID(), argMap.get(arg.getName().getValue()));
                }

                generateLocalVariableDefinitions(registry, typeMap, globalStrategy, fnBody, archetype.getVariables());

                // TODO: this should probably be a separate method in GlobalVariableStrategy
                globalStrategy.processPrelude(fnBody, null, archetype.getName(), selfVariable, GoBuiltins.Int);

                PlusCalStatementCodeGenVisitor codeGen = new PlusCalStatementCodeGenVisitor(
                        registry, typeMap, globalStrategy, archetype.getUID(), fnBody
                );
                for (PlusCalStatement statement : archetype.getBody()) {
                    statement.accept(codeGen);
                }

                fnBody.returnStmt(GoBuiltins.Nil);
            }
        }

        return module.getModule();
    }
}