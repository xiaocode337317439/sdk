// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/test_utilities/find_node.dart';
import 'package:nnbd_migration/instrumentation.dart';
import 'package:nnbd_migration/nnbd_migration.dart';
import 'package:nnbd_migration/nullability_state.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'abstract_context.dart';
import 'api_test_base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(_InstrumentationTest);
  });
}

class _InstrumentationClient implements NullabilityMigrationInstrumentation {
  final _InstrumentationTest test;

  _InstrumentationClient(this.test);

  @override
  void explicitTypeNullability(
      Source source, TypeAnnotation typeAnnotation, NullabilityNodeInfo node) {
    expect(source, test.source);
    expect(test.explicitTypeNullability, isNot(contains(typeAnnotation)));
    test.explicitTypeNullability[typeAnnotation] = node;
  }

  @override
  void externalDecoratedType(Element element, DecoratedTypeInfo decoratedType) {
    expect(test.externalDecoratedType, isNot(contains(element)));
    test.externalDecoratedType[element] = decoratedType;
  }

  @override
  void graphEdge(EdgeInfo edge, EdgeOriginInfo originInfo) {
    expect(test.edgeOrigin, isNot(contains(edge)));
    test.edges.add(edge);
    test.edgeOrigin[edge] = originInfo;
  }

  @override
  void immutableNodes(NullabilityNodeInfo never, NullabilityNodeInfo always) {
    test.never = never;
    test.always = always;
  }

  @override
  void implicitReturnType(
      Source source, AstNode node, DecoratedTypeInfo decoratedReturnType) {
    expect(source, test.source);
    expect(test.implicitReturnType, isNot(contains(node)));
    test.implicitReturnType[node] = decoratedReturnType;
  }

  @override
  void implicitType(
      Source source, AstNode node, DecoratedTypeInfo decoratedType) {
    expect(source, test.source);
    expect(test.implicitType, isNot(contains(node)));
    test.implicitType[node] = decoratedType;
  }

  @override
  void implicitTypeArguments(
      Source source, AstNode node, Iterable<DecoratedTypeInfo> types) {
    expect(source, test.source);
    expect(test.implicitTypeArguments, isNot(contains(node)));
    test.implicitTypeArguments[node] = types.toList();
  }

  @override
  void propagationStep(PropagationInfo info) {
    test.propagationSteps.add(info);
  }
}

@reflectiveTest
class _InstrumentationTest extends AbstractContextTest {
  NullabilityNodeInfo always;

  final Map<TypeAnnotation, NullabilityNodeInfo> explicitTypeNullability = {};

  final Map<Element, DecoratedTypeInfo> externalDecoratedType = {};

  final List<EdgeInfo> edges = [];

  final Map<AstNode, DecoratedTypeInfo> implicitReturnType = {};

  final Map<AstNode, DecoratedTypeInfo> implicitType = {};

  final Map<AstNode, List<DecoratedTypeInfo>> implicitTypeArguments = {};

  NullabilityNodeInfo never;

  final List<PropagationInfo> propagationSteps = [];

  final Map<EdgeInfo, EdgeOriginInfo> edgeOrigin = {};

  FindNode findNode;

  Source source;

  Future<void> analyze(String content) async {
    var sourcePath = convertPath('/home/test/lib/test.dart');
    newFile(sourcePath, content: content);
    var listener = new TestMigrationListener();
    var migration = NullabilityMigration(listener,
        instrumentation: _InstrumentationClient(this));
    var result = await session.getResolvedUnit(sourcePath);
    source = result.unit.declaredElement.source;
    findNode = FindNode(content, result.unit);
    migration.prepareInput(result);
    migration.processInput(result);
    migration.finish();
  }

  test_explicitTypeNullability() async {
    var content = '''
int x = 1;
int y = null;
''';
    await analyze(content);
    expect(explicitTypeNullability[findNode.typeAnnotation('int x')].isNullable,
        false);
    expect(explicitTypeNullability[findNode.typeAnnotation('int y')].isNullable,
        true);
  }

  test_externalDecoratedType() async {
    await analyze('''
main() {
  print(1);
}
''');
    expect(
        externalDecoratedType[findNode.simple('print').staticElement]
            .type
            .toString(),
        'void Function(Object)');
  }

  test_graphEdge() async {
    await analyze('''
int f(int x) => x;
''');
    var xNode = explicitTypeNullability[findNode.typeAnnotation('int x')];
    var returnNode = explicitTypeNullability[findNode.typeAnnotation('int f')];
    expect(
        edges.where(
            (e) => e.sourceNode == xNode && e.destinationNode == returnNode),
        hasLength(1));
  }

  test_graphEdge_guards() async {
    await analyze('''
int f(int i, int j) {
  if (i == null) {
    return j;
  }
  return 1;
}
''');
    var iNode = explicitTypeNullability[findNode.typeAnnotation('int i')];
    var jNode = explicitTypeNullability[findNode.typeAnnotation('int j')];
    var returnNode = explicitTypeNullability[findNode.typeAnnotation('int f')];
    var matchingEdges = edges
        .where((e) => e.sourceNode == jNode && e.destinationNode == returnNode)
        .toList();
    expect(matchingEdges, hasLength(1));
    expect(matchingEdges.single.guards, hasLength(1));
    expect(matchingEdges.single.guards.single, iNode);
  }

  test_graphEdge_hard() async {
    await analyze('''
int f(int x) => x;
''');
    var xNode = explicitTypeNullability[findNode.typeAnnotation('int x')];
    var returnNode = explicitTypeNullability[findNode.typeAnnotation('int f')];
    var matchingEdges = edges
        .where((e) => e.sourceNode == xNode && e.destinationNode == returnNode)
        .toList();
    expect(matchingEdges, hasLength(1));
    expect(matchingEdges.single.isUnion, false);
    expect(matchingEdges.single.isHard, true);
  }

  test_graphEdge_isSatisfied() async {
    await analyze('''
void f1(int i, bool b) {
  f2(i, b);
}
void f2(int j, bool b) {
  if (b) {
    f3(j);
  }
}
void f3(int k) {
  f4(k);
}
void f4(int l) {
  print(l.isEven);
}
main() {
  f1(null, false);
}
''');
    var iNode = explicitTypeNullability[findNode.typeAnnotation('int i')];
    var jNode = explicitTypeNullability[findNode.typeAnnotation('int j')];
    var kNode = explicitTypeNullability[findNode.typeAnnotation('int k')];
    var lNode = explicitTypeNullability[findNode.typeAnnotation('int l')];
    var iToJ = edges
        .where((e) => e.sourceNode == iNode && e.destinationNode == jNode)
        .single;
    var jToK = edges
        .where((e) => e.sourceNode == jNode && e.destinationNode == kNode)
        .single;
    var kToL = edges
        .where((e) => e.sourceNode == kNode && e.destinationNode == lNode)
        .single;
    expect(iNode.isNullable, true);
    expect(jNode.isNullable, true);
    expect(kNode.isNullable, false);
    expect(lNode.isNullable, false);
    expect(iToJ.isSatisfied, true);
    expect(jToK.isSatisfied, false);
    expect(kToL.isSatisfied, true);
  }

  test_graphEdge_origin() async {
    await analyze('''
int f(int x) => x;
''');
    var xNode = explicitTypeNullability[findNode.typeAnnotation('int x')];
    var returnNode = explicitTypeNullability[findNode.typeAnnotation('int f')];
    var matchingEdges = edges
        .where((e) => e.sourceNode == xNode && e.destinationNode == returnNode)
        .toList();
    var origin = edgeOrigin[matchingEdges.single];
    expect(origin.source, source);
    expect(origin.node, findNode.simple('x;'));
  }

  test_graphEdge_soft() async {
    await analyze('''
int f(int x, bool b) {
  if (b) return x;
  return 0;
}
''');
    var xNode = explicitTypeNullability[findNode.typeAnnotation('int x')];
    var returnNode = explicitTypeNullability[findNode.typeAnnotation('int f')];
    var matchingEdges = edges
        .where((e) => e.sourceNode == xNode && e.destinationNode == returnNode)
        .toList();
    expect(matchingEdges, hasLength(1));
    expect(matchingEdges.single.isUnion, false);
    expect(matchingEdges.single.isHard, false);
  }

  test_graphEdge_union() async {
    await analyze('''
class C {
  int i;
  C(this.i); /*constructor*/
}
''');
    var fieldNode = explicitTypeNullability[findNode.typeAnnotation('int')];
    var formalParamNode =
        implicitType[findNode.fieldFormalParameter('i); /*constructor*/')].node;
    var matchingEdges = edges
        .where((e) =>
            e.sourceNode == fieldNode && e.destinationNode == formalParamNode)
        .toList();
    expect(matchingEdges, hasLength(1));
    expect(matchingEdges.single.isUnion, true);
    expect(matchingEdges.single.isHard, true);
    matchingEdges = edges
        .where((e) =>
            e.sourceNode == formalParamNode && e.destinationNode == fieldNode)
        .toList();
    expect(matchingEdges, hasLength(1));
    expect(matchingEdges.single.isUnion, true);
    expect(matchingEdges.single.isHard, true);
  }

  test_immutableNode_always() async {
    await analyze('''
int x = null;
''');
    expect(always.isImmutable, true);
    expect(always.isNullable, true);
    var xNode = explicitTypeNullability[findNode.typeAnnotation('int')];
    var edge = edges.where((e) => e.destinationNode == xNode).single;
    expect(edge.sourceNode, always);
  }

  test_immutableNode_never() async {
    await analyze('''
bool f(int x) => x.isEven;
''');
    expect(never.isImmutable, true);
    expect(never.isNullable, false);
    var xNode = explicitTypeNullability[findNode.typeAnnotation('int')];
    var edge = edges.where((e) => e.sourceNode == xNode).single;
    expect(edge.destinationNode, never);
  }

  test_implicitReturnType_constructor() async {
    await analyze('''
class C {
  factory C() => f(true);
  C.named();
}
C f(bool b) => b ? C.named() : null;
''');
    var factoryReturnNode = implicitReturnType[findNode.constructor('C(')].node;
    var fReturnNode = explicitTypeNullability[findNode.typeAnnotation('C f')];
    expect(
        edges.where((e) =>
            e.sourceNode == fReturnNode &&
            e.destinationNode == factoryReturnNode),
        hasLength(1));
  }

  test_implicitReturnType_formalParameter() async {
    await analyze('''
Object f(callback()) => callback();
''');
    var paramReturnNode =
        implicitReturnType[findNode.functionTypedFormalParameter('callback())')]
            .node;
    var fReturnNode =
        explicitTypeNullability[findNode.typeAnnotation('Object')];
    expect(
        edges.where((e) =>
            e.sourceNode == paramReturnNode &&
            e.destinationNode == fReturnNode),
        hasLength(1));
  }

  test_implicitReturnType_function() async {
    await analyze('''
f() => 1;
Object g() => f();
''');
    var fReturnNode =
        implicitReturnType[findNode.functionDeclaration('f() =>')].node;
    var gReturnNode =
        explicitTypeNullability[findNode.typeAnnotation('Object')];
    expect(
        edges.where((e) =>
            e.sourceNode == fReturnNode && e.destinationNode == gReturnNode),
        hasLength(1));
  }

  test_implicitReturnType_functionExpression() async {
    await analyze('''
main() {
  int Function() f = () => g();
}
int g() => 1;
''');
    var fReturnNode =
        explicitTypeNullability[findNode.typeAnnotation('int Function')];
    var functionExpressionReturnNode =
        implicitReturnType[findNode.functionExpression('() => g()')].node;
    var gReturnNode = explicitTypeNullability[findNode.typeAnnotation('int g')];
    expect(
        edges.where((e) =>
            e.sourceNode == gReturnNode &&
            e.destinationNode == functionExpressionReturnNode),
        hasLength(1));
    expect(
        edges.where((e) =>
            e.sourceNode == functionExpressionReturnNode &&
            e.destinationNode == fReturnNode),
        hasLength(1));
  }

  test_implicitReturnType_functionTypeAlias() async {
    await analyze('''
typedef F();
Object f(F callback) => callback();
''');
    var typedefReturnNode =
        implicitReturnType[findNode.functionTypeAlias('F()')].node;
    var fReturnNode =
        explicitTypeNullability[findNode.typeAnnotation('Object')];
    expect(
        edges.where((e) =>
            e.sourceNode == typedefReturnNode &&
            e.destinationNode == fReturnNode),
        hasLength(1));
  }

  test_implicitReturnType_genericFunctionType() async {
    await analyze('''
Object f(Function() callback) => callback();
''');
    var callbackReturnNode =
        implicitReturnType[findNode.genericFunctionType('Function()')].node;
    var fReturnNode =
        explicitTypeNullability[findNode.typeAnnotation('Object')];
    expect(
        edges.where((e) =>
            e.sourceNode == callbackReturnNode &&
            e.destinationNode == fReturnNode),
        hasLength(1));
  }

  test_implicitReturnType_method() async {
    await analyze('''
abstract class Base {
  int f();
}
abstract class Derived extends Base {
  f /*derived*/();
}
''');
    var baseReturnNode =
        explicitTypeNullability[findNode.typeAnnotation('int')];
    var derivedReturnNode =
        implicitReturnType[findNode.methodDeclaration('f /*derived*/')].node;
    expect(
        edges.where((e) =>
            e.sourceNode == derivedReturnNode &&
            e.destinationNode == baseReturnNode),
        hasLength(1));
  }

  test_implicitType_catch_exception() async {
    await analyze('''
void f() {
  try {} catch (e) {
    Object o = e;
  }
}
''');
    var oNode = explicitTypeNullability[findNode.typeAnnotation('Object')];
    var eNode = implicitType[findNode.simple('e)')].node;
    expect(
        edges.where((e) => e.sourceNode == eNode && e.destinationNode == oNode),
        hasLength(1));
  }

  test_implicitType_catch_stackTrace() async {
    await analyze('''
void f() {
  try {} catch (e, st) {
    Object o = st;
  }
}
''');
    var oNode = explicitTypeNullability[findNode.typeAnnotation('Object')];
    var stNode = implicitType[findNode.simple('st)')].node;
    expect(
        edges
            .where((e) => e.sourceNode == stNode && e.destinationNode == oNode),
        hasLength(1));
  }

  test_implicitType_declaredIdentifier_forEachPartsWithDeclaration() async {
    await analyze('''
void f(List<int> l) {
  for (var x in l) {
    int y = x;
  }
}
''');
    var xNode = implicitType[(findNode.forStatement('for').forLoopParts
                as ForEachPartsWithDeclaration)
            .loopVariable]
        .node;
    var yNode = explicitTypeNullability[findNode.typeAnnotation('int y')];
    expect(
        edges.where((e) => e.sourceNode == xNode && e.destinationNode == yNode),
        hasLength(1));
  }

  test_implicitType_formalParameter() async {
    await analyze('''
abstract class Base {
  void f(int i);
}
abstract class Derived extends Base {
  void f(i); /*derived*/
}
''');
    var baseParamNode =
        explicitTypeNullability[findNode.typeAnnotation('int i')];
    var derivedParamNode =
        implicitType[findNode.simpleParameter('i); /*derived*/')].node;
    expect(
        edges.where((e) =>
            e.sourceNode == baseParamNode &&
            e.destinationNode == derivedParamNode),
        hasLength(1));
  }

  test_implicitType_namedParameter() async {
    await analyze('''
abstract class Base {
  void f(void callback({int i}));
}
abstract class Derived extends Base {
  void f(callback);
}
''');
    var baseParamParamNode =
        explicitTypeNullability[findNode.typeAnnotation('int i')];
    var derivedParamParamNode =
        implicitType[findNode.simpleParameter('callback)')]
            .namedParameter('i')
            .node;
    expect(
        edges.where((e) =>
            e.sourceNode == baseParamParamNode &&
            e.destinationNode == derivedParamParamNode),
        hasLength(1));
  }

  test_implicitType_positionalParameter() async {
    await analyze('''
abstract class Base {
  void f(void callback(int i));
}
abstract class Derived extends Base {
  void f(callback);
}
''');
    var baseParamParamNode =
        explicitTypeNullability[findNode.typeAnnotation('int i')];
    var derivedParamParamNode =
        implicitType[findNode.simpleParameter('callback)')]
            .positionalParameter(0)
            .node;
    expect(
        edges.where((e) =>
            e.sourceNode == baseParamParamNode &&
            e.destinationNode == derivedParamParamNode),
        hasLength(1));
  }

  test_implicitType_returnType() async {
    await analyze('''
abstract class Base {
  void f(int callback());
}
abstract class Derived extends Base {
  void f(callback);
}
''');
    var baseParamReturnNode =
        explicitTypeNullability[findNode.typeAnnotation('int callback')];
    var derivedParamReturnNode =
        implicitType[findNode.simpleParameter('callback)')].returnType.node;
    expect(
        edges.where((e) =>
            e.sourceNode == baseParamReturnNode &&
            e.destinationNode == derivedParamReturnNode),
        hasLength(1));
  }

  test_implicitType_typeArgument() async {
    await analyze('''
abstract class Base {
  void f(List<int> x);
}
abstract class Derived extends Base {
  void f(x); /*derived*/
}
''');
    var baseParamArgNode =
        explicitTypeNullability[findNode.typeAnnotation('int>')];
    var derivedParamArgNode =
        implicitType[findNode.simpleParameter('x); /*derived*/')]
            .typeArgument(0)
            .node;
    expect(
        edges.where((e) =>
            e.sourceNode == derivedParamArgNode &&
            e.destinationNode == baseParamArgNode),
        hasLength(1));
  }

  test_implicitType_variableDeclarationList() async {
    await analyze('''
void f(int i) {
  var j = i;
}
''');
    var iNode = explicitTypeNullability[findNode.typeAnnotation('int')];
    var jNode = implicitType[findNode.variableDeclarationList('j')].node;
    expect(
        edges.where((e) => e.sourceNode == iNode && e.destinationNode == jNode),
        hasLength(1));
  }

  test_implicitTypeArguments_genericFunctionCall() async {
    await analyze('''
List<T> g<T>(T t) {}
List<int> f() => g(null);
''');
    var implicitInvocationTypeArgumentNode =
        implicitTypeArguments[findNode.methodInvocation('g(null)')].single.node;
    var returnElementNode =
        explicitTypeNullability[findNode.typeAnnotation('int')];
    expect(edges.where((e) {
      var destination = e.destinationNode;
      return e.sourceNode == always &&
          destination is SubstitutionNodeInfo &&
          destination.innerNode == implicitInvocationTypeArgumentNode;
    }), hasLength(1));
    expect(edges.where((e) {
      var source = e.sourceNode;
      return source is SubstitutionNodeInfo &&
          source.innerNode == implicitInvocationTypeArgumentNode &&
          e.destinationNode == returnElementNode;
    }), hasLength(1));
  }

  test_implicitTypeArguments_genericMethodCall() async {
    await analyze('''
class C {
  List<T> g<T>(T t) {}
}
List<int> f(C c) => c.g(null);
''');
    var implicitInvocationTypeArgumentNode =
        implicitTypeArguments[findNode.methodInvocation('c.g(null)')]
            .single
            .node;
    var returnElementNode =
        explicitTypeNullability[findNode.typeAnnotation('int')];
    expect(edges.where((e) {
      var destination = e.destinationNode;
      return e.sourceNode == always &&
          destination is SubstitutionNodeInfo &&
          destination.innerNode == implicitInvocationTypeArgumentNode;
    }), hasLength(1));
    expect(edges.where((e) {
      var source = e.sourceNode;
      return source is SubstitutionNodeInfo &&
          source.innerNode == implicitInvocationTypeArgumentNode &&
          e.destinationNode == returnElementNode;
    }), hasLength(1));
  }

  test_implicitTypeArguments_instanceCreationExpression() async {
    await analyze('''
class C<T> {
  C(T t);
}
C<int> f() => C(null);
''');
    var implicitInvocationTypeArgumentNode =
        implicitTypeArguments[findNode.instanceCreation('C(null)')].single.node;
    var returnElementNode =
        explicitTypeNullability[findNode.typeAnnotation('int')];
    expect(edges.where((e) {
      var destination = e.destinationNode;
      return e.sourceNode == always &&
          destination is SubstitutionNodeInfo &&
          destination.innerNode == implicitInvocationTypeArgumentNode;
    }), hasLength(1));
    expect(
        edges.where((e) =>
            e.sourceNode == implicitInvocationTypeArgumentNode &&
            e.destinationNode == returnElementNode),
        hasLength(1));
  }

  test_implicitTypeArguments_listLiteral() async {
    await analyze('''
List<int> f() => [null];
''');
    var implicitListLiteralElementNode =
        implicitTypeArguments[findNode.listLiteral('[null]')].single.node;
    var returnElementNode =
        explicitTypeNullability[findNode.typeAnnotation('int')];
    expect(
        edges.where((e) =>
            e.sourceNode == always &&
            e.destinationNode == implicitListLiteralElementNode),
        hasLength(1));
    expect(
        edges.where((e) =>
            e.sourceNode == implicitListLiteralElementNode &&
            e.destinationNode == returnElementNode),
        hasLength(1));
  }

  test_implicitTypeArguments_mapLiteral() async {
    await analyze('''
Map<int, String> f() => {1: null};
''');
    var implicitMapLiteralTypeArguments =
        implicitTypeArguments[findNode.setOrMapLiteral('{1: null}')];
    expect(implicitMapLiteralTypeArguments, hasLength(2));
    var implicitMapLiteralKeyNode = implicitMapLiteralTypeArguments[0].node;
    var implicitMapLiteralValueNode = implicitMapLiteralTypeArguments[1].node;
    var returnKeyNode = explicitTypeNullability[findNode.typeAnnotation('int')];
    var returnValueNode =
        explicitTypeNullability[findNode.typeAnnotation('String')];
    expect(
        edges.where((e) =>
            e.sourceNode == never &&
            e.destinationNode == implicitMapLiteralKeyNode),
        hasLength(1));
    expect(
        edges.where((e) =>
            e.sourceNode == implicitMapLiteralKeyNode &&
            e.destinationNode == returnKeyNode),
        hasLength(1));
    expect(
        edges.where((e) =>
            e.sourceNode == always &&
            e.destinationNode == implicitMapLiteralValueNode),
        hasLength(1));
    expect(
        edges.where((e) =>
            e.sourceNode == implicitMapLiteralValueNode &&
            e.destinationNode == returnValueNode),
        hasLength(1));
  }

  test_implicitTypeArguments_setLiteral() async {
    await analyze('''
Set<int> f() => {null};
''');
    var implicitSetLiteralElementNode =
        implicitTypeArguments[findNode.setOrMapLiteral('{null}')].single.node;
    var returnElementNode =
        explicitTypeNullability[findNode.typeAnnotation('int')];
    expect(
        edges.where((e) =>
            e.sourceNode == always &&
            e.destinationNode == implicitSetLiteralElementNode),
        hasLength(1));
    expect(
        edges.where((e) =>
            e.sourceNode == implicitSetLiteralElementNode &&
            e.destinationNode == returnElementNode),
        hasLength(1));
  }

  test_implicitTypeArguments_typeAnnotation() async {
    await analyze('''
List<Object> f(List l) => l;
''');
    var implicitListElementType =
        implicitTypeArguments[findNode.typeAnnotation('List l')].single.node;
    var implicitReturnElementType =
        explicitTypeNullability[findNode.typeAnnotation('Object')];
    expect(
        edges.where((e) =>
            e.sourceNode == implicitListElementType &&
            e.destinationNode == implicitReturnElementType),
        hasLength(1));
  }

  test_propagationStep() async {
    await analyze('''
int x = null;
''');
    var xNode = explicitTypeNullability[findNode.typeAnnotation('int')];
    var step = propagationSteps.where((s) => s.node == xNode).single;
    expect(step.newState, NullabilityState.ordinaryNullable);
    expect(step.reason, StateChangeReason.downstream);
    expect(step.edge.sourceNode, always);
    expect(step.edge.destinationNode, xNode);
  }

  test_substitutionNode() async {
    await analyze('''
class C<T> {
  void f(T t) {}
}
voig g(C<int> x, int y) {
  x.f(y);
}
''');
    var yNode = explicitTypeNullability[findNode.typeAnnotation('int y')];
    var edge = edges.where((e) => e.sourceNode == yNode).single;
    var sNode = edge.destinationNode as SubstitutionNodeInfo;
    expect(sNode.innerNode,
        explicitTypeNullability[findNode.typeAnnotation('int>')]);
    expect(sNode.outerNode,
        explicitTypeNullability[findNode.typeAnnotation('T t')]);
  }
}