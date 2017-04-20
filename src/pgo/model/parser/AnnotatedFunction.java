package pgo.model.parser;

import java.util.Vector;

import pgo.model.intermediate.PGoFunction;
import pgo.model.intermediate.PGoType;
import pgo.parser.PGoParseException;

/**
 * Represents the information of a function from the pluscal annotations.
 *
 */
public class AnnotatedFunction {

	// list of types of the function argument
	private Vector<PGoType> args;

	// the name of function
	private String name;

	// the return type of function
	private PGoType rType;

	// the line number of the annotation
	private int line;

	protected AnnotatedFunction(String[] parts, int line) throws PGoParseException {
		args = new Vector<PGoType>();
		this.line = line;
		rType = PGoType.VOID;
		int i = 1;
		if (!parts[i].contains("()")) {
			rType = PGoType.inferFromGoTypeName(parts[1]);
			if (rType.isUndetermined()) {
				throw new PGoParseException(
						"Unknown type \"" + parts[1] + "\" specified for return type in function annotation", line);
			}
			++i;
		}

		name = parts[i].substring(0, parts[i].length() - 2);

		for (int j=1; i+j < parts.length; ++j) {
			PGoType atype = PGoType.inferFromGoTypeName(parts[i + j]);
			if (atype.isUndetermined()) {
				throw new PGoParseException("Unknown type \"" + parts[i + j]
						+ "\" specified for parameter " + j + " in function annotation", line);
			}
			args.add(atype);
		}
	}

	public String getName() {
		return name;
	}

	public Vector<PGoType> getArgTypes() {
		return args;
	}

	public PGoType getReturnType() {
		return rType;
	}

	public int getLine() {
		return line;
	}

	// Fill the PGoFunction with information of this annotation
	public void fillFunction(PGoFunction fun) {
		// TODO Auto-generated method stub

	}

	public static AnnotatedFunction parse(String[] parts, int line) throws PGoParseException {
		assert (parts[0].toLowerCase().equals("func"));

		boolean error = false;
		if (parts.length < 2) {
			error = true;
		} else if (parts.length == 2 && !parts[1].contains("()")) {
			error = true;
		} else {
			if (!parts[1].contains("()") && !parts[2].contains("()")) {
				error = true;
			}
		}
		if (error) {
			throw new PGoParseException("Annotation of \"func\" requires (<rtype>)? <funcname>() (<argtype>)?+",
					line);
		}
		return new AnnotatedFunction(parts, line);
	}

}