package pgo.formatters;

import pgo.TODO;
import pgo.model.mpcal.ModularPlusCalYield;
import pgo.model.pcal.*;
import pgo.model.tla.TLAExpression;

import java.io.IOException;
import java.util.List;

public class PlusCalStatementFormattingVisitor extends PlusCalStatementVisitor<Void, IOException> {
	private final IndentingWriter out;

	public PlusCalStatementFormattingVisitor(IndentingWriter out) {
		this.out = out;
	}

	@Override
	public Void visit(PlusCalLabeledStatements labeledStatements) throws IOException {
		labeledStatements.getLabel().accept(new PlusCalNodeFormattingVisitor(out));
		out.write("{");
		try(IndentingWriter.Indent i_ = out.indent()) {
			for(PlusCalStatement stmt : labeledStatements.getStatements()) {
				out.newLine();
				stmt.accept(this);
			}
		}
		out.newLine();
		out.write("}");
		return null;
	}

	@Override
	public Void visit(PlusCalWhile plusCalWhile) throws IOException {
		out.write("while (");
		plusCalWhile.getCondition().accept(new TLAExpressionFormattingVisitor(out));
		out.write(") {");
		try(IndentingWriter.Indent i_ = out.indent()) {
			for(PlusCalStatement stmt : plusCalWhile.getBody()) {
				out.newLine();
				stmt.accept(this);
			}
			out.newLine();
		}
		out.write("}");
		return null;
	}

	@Override
	public Void visit(PlusCalIf plusCalIf) throws IOException {
		out.write("if (");
		plusCalIf.getCondition().accept(new TLAExpressionFormattingVisitor(out));
		out.write(") {");
		try(IndentingWriter.Indent i_ = out.indent()) {
			for(PlusCalStatement stmt : plusCalIf.getYes()){
				out.newLine();
				stmt.accept(new PlusCalStatementFormattingVisitor(out));
			}
			out.newLine();
			out.write("}");
		}
		if(!plusCalIf.getNo().isEmpty()) {
			out.write(" else {");
			try(IndentingWriter.Indent i_ = out.indent()) {
				for(PlusCalStatement stmt : plusCalIf.getYes()){
					out.newLine();
					stmt.accept(new PlusCalStatementFormattingVisitor(out));
				}
				out.newLine();
				out.write("}");
			}
		}
		out.write(";");
		return null;
	}

	@Override
	public Void visit(PlusCalEither plusCalEither) throws IOException {
		throw new TODO();
	}

	@Override
	public Void visit(PlusCalAssignment plusCalAssignment) throws IOException {
		List<PlusCalAssignmentPair> pairs = plusCalAssignment.getPairs();
		
		pairs.get(0).accept(new PlusCalNodeFormattingVisitor(out));
		
		for(PlusCalAssignmentPair pair : pairs.subList(1, pairs.size())) {
			out.write(" || ");
			pair.accept(new PlusCalNodeFormattingVisitor(out));
		}
		out.write(";");
		return null;
	}

	@Override
	public Void visit(PlusCalReturn plusCalReturn) throws IOException {
		out.write("return;");
		return null;
	}

	@Override
	public Void visit(PlusCalSkip skip) throws IOException {
		throw new TODO();
	}

	@Override
	public Void visit(PlusCalCall plusCalCall) throws IOException {
		out.write("call ");
		out.write(plusCalCall.getTarget());
		out.write("(");

		for (TLAExpression arg : plusCalCall.getArguments()) {
			arg.accept(new TLANodeFormattingVisitor(out));
		}

		out.write(");");
		return null;
	}

	@Override
	public Void visit(PlusCalMacroCall macroCall) throws IOException {
		throw new TODO();
	}

	@Override
	public Void visit(PlusCalWith with) throws IOException {
		throw new TODO();
	}

	@Override
	public Void visit(PlusCalPrint plusCalPrint) throws IOException {
		out.write("print ");
		plusCalPrint.getValue().accept(new TLAExpressionFormattingVisitor(out));
		return null;
	}

	@Override
	public Void visit(PlusCalAssert plusCalAssert) throws IOException {
		throw new TODO();
	}

	@Override
	public Void visit(PlusCalAwait plusCalAwait) throws IOException {
		throw new TODO();
	}

	@Override
	public Void visit(PlusCalGoto plusCalGoto) throws IOException {
		throw new TODO();
	}

	@Override
	public Void visit(ModularPlusCalYield modularPlusCalYield) throws IOException {
		throw new TODO();
	}
}
