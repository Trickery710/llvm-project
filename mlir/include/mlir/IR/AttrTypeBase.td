//===-- AttrTypeBase.td - Base Attr/Type definition file ---*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the base set of constructs for defining Attribute and
// Type classes.
//
//===----------------------------------------------------------------------===//

#ifndef ATTRTYPEBASE_TD
#define ATTRTYPEBASE_TD

include "mlir/IR/OpBase.td"

//-------------------------------------------------------------------------===//
// AttrTrait definitions
//===----------------------------------------------------------------------===//

// These classes are used to define attribute specific traits.
class NativeAttrTrait<string name> : NativeTrait<name, "Attribute">;
class ParamNativeAttrTrait<string prop, string params>
    : ParamNativeTrait<prop, params, "Attribute">;
class GenInternalAttrTrait<string prop> : GenInternalTrait<prop, "Attribute">;
class PredAttrTrait<string descr, Pred pred> : PredTrait<descr, pred>;

//===----------------------------------------------------------------------===//
// TypeTrait definitions
//===----------------------------------------------------------------------===//

// These classes are used to define type specific traits.
class NativeTypeTrait<string name> : NativeTrait<name, "Type">;
class ParamNativeTypeTrait<string prop, string params>
    : ParamNativeTrait<prop, params, "Type">;
class GenInternalTypeTrait<string prop> : GenInternalTrait<prop, "Type">;
class PredTypeTrait<string descr, Pred pred> : PredTrait<descr, pred>;

//===----------------------------------------------------------------------===//
// Builders
//===----------------------------------------------------------------------===//

// Class for defining a custom getter.
//
// TableGen generates several generic getter methods for each attribute and type
// by default, corresponding to the specified dag parameters. If the default
// generated ones cannot cover some use case, custom getters can be defined
// using instances of this class.
//
// The signature of the `get` is always either:
//
// ```c++
// static <ClassName> get(MLIRContext *context, <other-parameters>...) {
//   <body>...
// }
// ```
//
// or:
//
// ```c++
// static <ClassName> get(MLIRContext *context, <parameters>...);
// ```
//
// To define a custom getter, the parameter list and body should be passed
// in as separate template arguments to this class. The parameter list is a
// TableGen DAG with `ins` operation with named arguments, which has either:
//   - string initializers ("Type":$name) to represent a typed parameter, or
//   - CArg-typed initializers (CArg<"Type", "default">:$name) to represent a
//     typed parameter that may have a default value.
// The type string is used verbatim to produce code and, therefore, must be a
// valid C++ type. It is used inside the C++ namespace of the parent Type's
// dialect; explicit namespace qualification like `::mlir` may be necessary if
// Types are not placed inside the `mlir` namespace. The default value string is
// used verbatim to produce code and must be a valid C++ initializer the given
// type. For example, the following signature specification
//
// ```
// AttrOrTypeBuilder<(ins "int":$integerArg, CArg<"float", "3.0f">:$floatArg)>
// ```
//
// has an integer parameter and a float parameter with a default value.
//
// If an empty string is passed in for `body`, then *only* the builder
// declaration will be generated; this provides a way to define complicated
// builders entirely in C++. If a `body` string is provided, the `Base::get`
// method should be invoked using `$_get`, e.g.:
//
// ```
// AttrOrTypeBuilder<(ins "int":$integerArg, CArg<"float", "3.0f">:$floatArg), [{
//   return $_get($_ctxt, integerArg, floatArg);
// }]>
// ```
//
// This is necessary because the `body` is also used to generate `getChecked`
// methods, which have a different underlying `Base::get*` call.
//
class AttrOrTypeBuilder<dag parameters, code bodyCode = ""> {
  dag dagParams = parameters;
  code body = bodyCode;

  // The context parameter can be inferred from one of the other parameters and
  // is not implicitly added to the parameter list.
  bit hasInferredContextParam = 0;
}
class AttrBuilder<dag parameters, code bodyCode = "">
  : AttrOrTypeBuilder<parameters, bodyCode>;
class TypeBuilder<dag parameters, code bodyCode = "">
  : AttrOrTypeBuilder<parameters, bodyCode>;

// A class of AttrOrTypeBuilder that is able to infer the MLIRContext parameter
// from one of the other builder parameters. Instances of this builder do not
// have `MLIRContext *` implicitly added to the parameter list.
class AttrOrTypeBuilderWithInferredContext<dag parameters, code bodyCode = "">
  : TypeBuilder<parameters, bodyCode> {
  let hasInferredContextParam = 1;
}
class AttrBuilderWithInferredContext<dag parameters, code bodyCode = "">
  : AttrOrTypeBuilderWithInferredContext<parameters, bodyCode>;
class TypeBuilderWithInferredContext<dag parameters, code bodyCode = "">
  : AttrOrTypeBuilderWithInferredContext<parameters, bodyCode>;

//===----------------------------------------------------------------------===//
// Definitions
//===----------------------------------------------------------------------===//

// Define a new attribute or type, named `name`, that inherits from the given
// C++ base class.
class AttrOrTypeDef<string valueType, string name, list<Trait> defTraits,
                    string baseCppClass> {
  // The name of the C++ base class to use for this def.
  string cppBaseClassName = baseCppClass;

  // Additional, longer human-readable description of what the def does.
  string description = "";

  // Name of storage class to generate or use.
  string storageClass = name # valueType # "Storage";

  // Namespace (withing dialect c++ namespace) in which the storage class
  // resides.
  string storageNamespace = "detail";

  // Specify if the storage class is to be generated.
  bit genStorageClass = 1;

  // Specify that the generated storage class has a constructor which is written
  // in C++.
  bit hasStorageCustomConstructor = 0;

  // The list of parameters for this type. Parameters will become both
  // parameters to the get() method and storage class member variables.
  //
  // The format of this dag is:
  //    (ins
  //        "<c++ type>":$param1Name,
  //        "<c++ type>":$param2Name,
  //        AttrOrTypeParameter<"c++ type", "param description">:$param3Name)
  // AttrOrTypeParameters (or more likely one of their subclasses) are required
  // to add more information about the parameter, specifically:
  //  - Documentation
  //  - Code to allocate the parameter (if allocation is needed in the storage
  //    class constructor)
  //
  // For example:
  //    (ins "int":$width,
  //         ArrayRefParameter<"bool", "list of bools">:$yesNoArray)
  //
  // (ArrayRefParameter is a subclass of AttrOrTypeParameter which has
  // allocation code for re-allocating ArrayRefs. It is defined below.)
  dag parameters = (ins);

  // Custom builder methods.
  // In addition to the custom builders provided here, and unless
  // skipDefaultBuilders is set, a default builder is generated with the
  // following signature:
  //
  // ```c++
  // static <ClassName> get(MLIRContext *, <parameters>);
  // ```
  //
  // Note that builders should only be provided when a def has parameters.
  list<AttrOrTypeBuilder> builders = ?;

  // The list of traits attached to this def.
  list<Trait> traits = defTraits;

  // Use the lowercased name as the keyword for parsing/printing. Specify only
  // if you want tblgen to generate declarations and/or definitions of
  // the printer/parser. If specified and the Attribute or Type contains
  // parameters, `assemblyFormat` or `hasCustomAssemblyFormat` must also be
  // specified.
  string mnemonic = ?;

  // Custom assembly format. Requires 'mnemonic' to be specified. Cannot be
  // specified at the same time as 'hasCustomAssemblyFormat'. The generated
  // printer requires 'genAccessors' to be true.
  string assemblyFormat = ?;
  /// This field indicates that the attribute or type has a custom assembly format
  /// implemented in C++. When set to `1` a `parse` and `print` method are generated
  /// on the generated class. The attribute or type should implement these methods to
  /// support the custom format.
  bit hasCustomAssemblyFormat = 0;

  // If set, generate accessors for each parameter.
  bit genAccessors = 1;

  // Avoid generating default get/getChecked functions. Custom get methods must
  // be provided.
  bit skipDefaultBuilders = 0;

  // Generate the verify and getChecked methods.
  bit genVerifyDecl = 0;

  // Extra code to include in the class declaration.
  code extraClassDeclaration = [{}];
}

// Define a new attribute, named `name`, belonging to `dialect` that inherits
// from the given C++ base class.
class AttrDef<Dialect dialect, string name, list<Trait> traits = [],
              string baseCppClass = "::mlir::Attribute">
    : DialectAttr<dialect, CPred<"">, /*descr*/"">,
      AttrOrTypeDef<"Attr", name, traits, baseCppClass> {
  // The name of the C++ Attribute class.
  string cppClassName = name # "Attr";
  let storageType = dialect.cppNamespace # "::" # name # "Attr";

  // The underlying C++ value type
  let returnType = dialect.cppNamespace # "::" # cppClassName;

  // Make it possible to use such attributes as parameters for other attributes.
  string cppType = dialect.cppNamespace # "::" # cppClassName;

  // The call expression to convert from the storage type to the return
  // type. For example, an enum can be stored as an int but returned as an
  // enum class.
  //
  // Format: $_self will be expanded to the attribute.
  //
  // For example, `$_self.getValue().getSExtValue()` for `IntegerAttr val` will
  // expand to `getAttrOfType<IntegerAttr>("val").getValue().getSExtValue()`.
  let convertFromStorage = "$_self.cast<" # dialect.cppNamespace #
                                 "::" # cppClassName # ">()";

  // A code block used to build the value 'Type' of an Attribute when
  // initializing its storage instance. This field is optional, and if not
  // present the attribute will have its value type set to `NoneType`. This code
  // block may reference any of the attributes parameters via
  // `$_<parameter-name`. If one of the parameters of the attribute is of type
  // `AttributeSelfTypeParameter`, this field is ignored.
  code typeBuilder = ?;

  // The predicate for when this def is used as a constraint.
  let predicate = CPred<"$_self.isa<" # dialect.cppNamespace #
                                 "::" # cppClassName # ">()">;
}

// Define a new type, named `name`, belonging to `dialect` that inherits from
// the given C++ base class.
class TypeDef<Dialect dialect, string name, list<Trait> traits = [],
              string baseCppClass = "::mlir::Type">
    : DialectType<dialect, CPred<"">, /*descr*/"", name # "Type">,
      AttrOrTypeDef<"Type", name, traits, baseCppClass> {
  // Make it possible to use such type as parameters for other types.
  string cppType = dialect.cppNamespace # "::" # cppClassName;

  // A constant builder provided when the type has no parameters.
  let builderCall = !if(!empty(parameters),
                           "$_builder.getType<" # dialect.cppNamespace #
                               "::" # cppClassName # ">()",
                           "");
  // The predicate for when this def is used as a constraint.
  let predicate = CPred<"$_self.isa<" # dialect.cppNamespace #
                                 "::" # cppClassName # ">()">;
}

//===----------------------------------------------------------------------===//
// Parameters
//===----------------------------------------------------------------------===//

// 'Parameters' should be subclasses of this or simple strings (which is a
// shorthand for AttrOrTypeParameter<"C++Type">).
class AttrOrTypeParameter<string type, string desc, string accessorType = ""> {
  // Custom memory allocation code for storage constructor.
  code allocator = ?;
  // Comparator used to compare two instances for equality. By default, it uses
  // the C++ equality operator.
  code comparator = ?;
  // The C++ type of this parameter.
  string cppType = type;
  // The C++ type of the accessor for this parameter.
  string cppAccessorType = !if(!empty(accessorType), type, accessorType);
  // The C++ storage type of of this parameter if it is a reference, e.g.
  // `std::string` for `StringRef` or `SmallVector` for `ArrayRef`.
  string cppStorageType = ?;
  // The C++ code to convert from the storage type to the parameter type.
  string convertFromStorage = "$_self";
  // One-line human-readable description of the argument.
  string summary = desc;
  // The format string for the asm syntax (documentation only).
  string syntax = ?;
  // The default parameter parser is `::mlir::FieldParser<T>::parse($_parser)`,
  // which returns `FailureOr<T>`. Specialize `FieldParser` to support parsing
  // for your type. Or you can provide a customer printer. For attributes,
  // "$_type" will be replaced with the required attribute type.
  string parser = ?;
  // The default parameter printer is `$_printer << $_self`. Overload the stream
  // operator of `AsmPrinter` as necessary to print your type. Or you can
  // provide a custom printer.
  string printer = ?;
  // Mark a parameter as optional. The C++ type of parameters marked as optional
  // must be default constructible and be contextually convertible to `bool`.
  // Any `Optional<T>` and any attribute type satisfies these requirements.
  bit isOptional = 0;
  // Provide a default value for the parameter. Parameters with default values
  // are considered optional. If a value was not parsed for the parameter, it
  // will be set to the default value. Parameters equal to their default values
  // are elided when printing. Equality is checked using the `comparator` field,
  // which by default is the C++ equality operator. The current MLIR context is
  // made available through `$_ctx`, e.g., for constructing default values for
  // attributes and types.
  string defaultValue = ?;
}
class AttrParameter<string type, string desc, string accessorType = "">
 : AttrOrTypeParameter<type, desc, accessorType>;
class TypeParameter<string type, string desc, string accessorType = "">
 : AttrOrTypeParameter<type, desc, accessorType>;

// For StringRefs, which require allocation.
class StringRefParameter<string desc = ""> :
    AttrOrTypeParameter<"::llvm::StringRef", desc> {
  let allocator = [{$_dst = $_allocator.copyInto($_self);}];
  let printer = [{$_printer << '"' << $_self << '"';}];
  let cppStorageType = "std::string";
}

// For APFloats, which require comparison.
class APFloatParameter<string desc> :
    AttrOrTypeParameter<"::llvm::APFloat", desc> {
  let comparator = "$_lhs.bitwiseIsEqual($_rhs)";
}

// For standard ArrayRefs, which require allocation.
class ArrayRefParameter<string arrayOf, string desc = ""> :
    AttrOrTypeParameter<"::llvm::ArrayRef<" # arrayOf # ">", desc> {
  let allocator = [{$_dst = $_allocator.copyInto($_self);}];
  let cppStorageType = "::llvm::SmallVector<" # arrayOf # ">";
}

// For classes which require allocation and have their own allocateInto method.
class SelfAllocationParameter<string type, string desc> :
    AttrOrTypeParameter<type, desc> {
  let allocator = [{$_dst = $_self.allocateInto($_allocator);}];
}

// For ArrayRefs which contain things which allocate themselves.
class ArrayRefOfSelfAllocationParameter<string arrayOf, string desc> :
    AttrOrTypeParameter<"::llvm::ArrayRef<" # arrayOf # ">", desc> {
  let allocator = [{
    llvm::SmallVector<}] # arrayOf # [{, 4> tmpFields;
    for (size_t i = 0, e = $_self.size(); i < e; ++i)
      tmpFields.push_back($_self[i].allocateInto($_allocator));
    $_dst = $_allocator.copyInto(ArrayRef<}] # arrayOf # [{>(tmpFields));
  }];
}

// An optional parameter.
class OptionalParameter<string type, string desc = ""> :
    AttrOrTypeParameter<type, desc> {
  let isOptional = 1;
}

// A parameter with a default value.
class DefaultValuedParameter<string type, string value, string desc = ""> :
    AttrOrTypeParameter<type, desc> {
  let isOptional = 1;
  let defaultValue = value;
}

// This is a special parameter used for AttrDefs that represents a `mlir::Type`
// that is also used as the value `Type` of the attribute. Only one parameter
// of the attribute may be of this type.
class AttributeSelfTypeParameter<string desc,
                                 string derivedType = "::mlir::Type"> :
    AttrOrTypeParameter<derivedType, desc> {}

#endif // ATTRTYPEBASE_TD
