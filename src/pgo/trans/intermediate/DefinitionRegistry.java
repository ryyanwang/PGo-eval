package pgo.trans.intermediate;

import pgo.InternalCompilerError;
import pgo.model.golang.type.GoType;
import pgo.model.pcal.PlusCalProcedure;
import pgo.model.tla.*;
import pgo.scope.UID;

import java.util.*;

public class DefinitionRegistry {
	private Map<String, TLAModule> modules;
	private Map<UID, TLAUnit> definitions;
	private Map<UID, OperatorAccessor> operators;
	private Map<UID, GoType> globalVariableTypes;
	private Set<UID> localVariables;
	private Map<UID, String> constants;
	private Map<UID, TLAExpression> constantValues;
	private Map<UID, UID> references;
	private Map<String, PlusCalProcedure> procedures;
	private Map<UID, Integer> labelsToLockGroups;
	private Map<Integer, Set<UID>> lockGroupsToVariableReads;
	private Map<Integer, Set<UID>> lockGroupsToVariableWrites;
	private Set<UID> protectedGlobalVariables;

	public DefinitionRegistry() {
		this.modules = new HashMap<>();
		this.definitions = new HashMap<>();
		this.operators = new HashMap<>();
		this.references = new HashMap<>();
		this.procedures = new HashMap<>();
		this.globalVariableTypes = new HashMap<>();
		this.localVariables = new HashSet<>();
		this.constants = new HashMap<>();
		this.constantValues = new HashMap<>();
		this.labelsToLockGroups = new HashMap<>();
		this.lockGroupsToVariableReads = new HashMap<>();
		this.lockGroupsToVariableWrites = new HashMap<>();
		this.protectedGlobalVariables = new HashSet<>();
	}

	public Map<UID, UID> getReferences() {
		return references;
	}

	public void addModule(TLAModule module) {
		if (!modules.containsKey(module.getName().getId())) {
			modules.put(module.getName().getId(), module);
		}
	}

	public void addOperatorDefinition(TLAOperatorDefinition def) {
		if (!definitions.containsKey(def.getUID())) {
			definitions.put(def.getUID(), def);
		}
	}

	public void addOperator(UID uid, OperatorAccessor op) {
		operators.put(uid, op);
	}

	public void addFunctionDefinition(TLAFunctionDefinition def) {
		if (!definitions.containsKey(def.getUID())) {
			definitions.put(def.getUID(), def);
		}
	}

	public void addProcedure(PlusCalProcedure proc) {
		procedures.put(proc.getName(), proc);
	}

	public void addGlobalVariable(UID uid) {
		globalVariableTypes.put(uid, null);
	}

	public void updateGlobalVariableType(UID uid, GoType type) {
		if (!globalVariableTypes.containsKey(uid)) {
			throw new InternalCompilerError();
		}
		globalVariableTypes.put(uid, type);
	}

	public void addLocalVariable(UID uid) {
		localVariables.add(uid);
	}

	public void addConstant(UID uid, String name) {
		constants.put(uid, name);
	}

	public UID followReference(UID from) {
		if (!references.containsKey(from)) {
			throw new InternalCompilerError();
		}
		return references.get(from);
	}

	public OperatorAccessor findOperator(UID id) {
		if (!operators.containsKey(id)) {
			throw new InternalCompilerError();
		}
		return operators.get(id);
	}

	public TLAModule findModule(String name) {
		return modules.get(name);
	}

	public PlusCalProcedure findProcedure(String name) {
		return procedures.get(name);
	}

	public boolean isGlobalVariable(UID ref) {
		return globalVariableTypes.containsKey(ref);
	}

	public GoType getGlobalVariableType(UID uid) {
		return globalVariableTypes.get(uid);
	}

	public boolean isLocalVariable(UID ref) {
		return localVariables.contains(ref);
	}

	public boolean isConstant(UID ref) {
		return constants.containsKey(ref);
	}

	public Set<UID> getConstants() {
		return constants.keySet();
	}

	public String getConstantName(UID id) {
		if (!constants.containsKey(id)) {
			throw new InternalCompilerError();
		}
		return constants.get(id);
	}

	public void setConstantValue(UID id, TLAExpression value) {
		constantValues.put(id, value);
	}

	public TLAExpression getConstantValue(UID id) {
		if (!constantValues.containsKey(id)) {
			throw new InternalCompilerError();
		}
		return constantValues.get(id);
	}

	public Set<UID> globalVariables() {
		return globalVariableTypes.keySet();
	}

	public void addLabelToLockGroup(UID labelUID, int lockGroup) {
		if (labelsToLockGroups.containsKey(labelUID)) {
			throw new InternalCompilerError();
		}
		labelsToLockGroups.put(labelUID, lockGroup);
	}

	public int getLockGroup(UID labelUID) {
		return labelsToLockGroups.get(labelUID);
	}

	public int getNumberOfLockGroups() {
		return 1 + labelsToLockGroups.values().stream()
				.max(Comparator.comparingInt(Integer::intValue))
				.orElse(-1);
	}

	public int getLockGroupOrDefault(UID labelUID, int defaultValue) {
		return labelsToLockGroups.getOrDefault(labelUID, defaultValue);
	}

	public void addVariableReadToLockGroup(UID varUID, int lockGroup) {
		lockGroupsToVariableReads.putIfAbsent(lockGroup, new HashSet<>());
		lockGroupsToVariableReads.get(lockGroup).add(varUID);
	}

	public void addVariableWriteToLockGroup(UID varUID, int lockGroup) {
		lockGroupsToVariableWrites.putIfAbsent(lockGroup, new HashSet<>());
		lockGroupsToVariableWrites.get(lockGroup).add(varUID);
	}

	public Set<UID> getVariableReadsInLockGroup(int lockGroup) {
		return Collections.unmodifiableSet(lockGroupsToVariableReads.getOrDefault(lockGroup, Collections.emptySet()));
	}

	public Set<UID> getVariableWritesInLockGroup(int lockGroup) {
		return Collections.unmodifiableSet(lockGroupsToVariableWrites.getOrDefault(lockGroup, Collections.emptySet()));
	}

	public void addProtectedGlobalVariable(UID varUID) {
		protectedGlobalVariables.add(varUID);
	}

	public boolean isGlobalVariableProtected(UID varUID) {
		return protectedGlobalVariables.contains(varUID);
	}

	public Set<UID> protectedGlobalVariables() {
		return Collections.unmodifiableSet(protectedGlobalVariables);
	}
}