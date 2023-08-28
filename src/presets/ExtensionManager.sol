// SPDX-License-Identifier: MIT
// @author: thirdweb (https://github.com/thirdweb-dev/dynamic-contracts)

pragma solidity ^0.8.0;

import "../interface/IExtensionManager.sol";
import "../interface/IRouterState.sol";
import "../interface/IRouterStateGetters.sol";
import "../lib/ExtensionManagerStorage.sol";

contract ExtensionManager is IExtensionManager, IRouterState, IRouterStateGetters {

    using StringSet for StringSet.Set;

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns all extensions of the Router.
    function getAllExtensions() external view override returns (Extension[] memory allExtensions) {

        string[] memory names = _extensionManagerStorage().extensionNames.values();
        uint256 len = names.length;
        
        allExtensions = new Extension[](len);

        for (uint256 i = 0; i < len; i += 1) {
            allExtensions[i] = _getExtension(names[i]);
        }
    }

    /// @dev Returns the extension metadata for a given function.
    function getMetadataForFunction(bytes4 functionSelector) public view returns (ExtensionMetadata memory) {
        return _extensionManagerStorage().extensionMetadata[functionSelector];
    }

    /// @dev Returns the extension metadata and functions for a given extension.
    function getExtension(string memory extensionName) public view returns (Extension memory) {
        return _getExtension(extensionName);
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Add a new extension to the router.
     */
    function addExtension(Extension memory _extension) external {    
        // Check: extension namespace must not already exist.
        // Check: provided extension namespace must not be empty.
        // Check: provided extension implementation must be non-zero.
        // Store: new extension name.
        require(_canAddExtension(_extension), "ExtensionManager: cannot add extension.");

        // 1. Store: metadata for extension.
        _setMetadataForExtension(_extension.metadata.name, _extension.metadata);

        uint256 len = _extension.functions.length;
        for (uint256 i = 0; i < len; i += 1) {
            // 2. Store: function for extension.
            _addFunctionToExtension(_extension.metadata.name, _extension.functions[i]);
            // 3. Store: metadata for function.
            _setMetadataForFunction(_extension.functions[i].functionSelector, _extension.metadata);
        }

        emit ExtensionAdded(_extension.metadata.name, _extension.metadata.implementation, _extension);
    }

    /**
     *  @notice Fully replace an existing extension of the router.
     */
    function replaceExtension(Extension memory _extension) external {
        // Check: extension namespace must already exist.
        // Check: provided extension implementation must be non-zero.
        require(_canReplaceExtension(_extension), "ExtensionManager: cannot replace extension.");
        
        // 1. Store: metadata for extension.
        _setMetadataForExtension(_extension.metadata.name, _extension.metadata);
        // 2. Delete: existing extension.functions.
        _removeAllFunctionsFromExtension(_extension.metadata.name);
        
        uint256 len = _extension.functions.length;
        for (uint256 i = 0; i < len; i += 1) {
            // 2. Delete: metadata for function.
            _deleteMetadataForFunction(_extension.functions[i].functionSelector);
            // 3. Store: function for extension.
            _addFunctionToExtension(_extension.metadata.name, _extension.functions[i]);
            // 4. Store: metadata for function.
            _setMetadataForFunction(_extension.functions[i].functionSelector, _extension.metadata);
        }

        emit ExtensionReplaced(_extension.metadata.name, _extension.metadata.implementation, _extension);
    }

    /**
     *  @notice Remove an existing extension from the router.
     */
    function removeExtension(string memory _extensionName) external {
        // Check: extension namespace must already exist.
        // Delete: extension namespace.
        require(_canRemoveExtension(_extensionName), "ExtensionManager: cannot remove extension.");

        Extension memory extension = _extensionManagerStorage().extensions[_extensionName];

        // 1. Delete: metadata for extension.
        _deleteMetadataForExtension(_extensionName);
        // 2. Delete: all functions of extension.
        _removeAllFunctionsFromExtension(_extensionName);

        uint256 len = extension.functions.length;
        for(uint256 i = 0; i < len; i += 1) {
            // 3. Delete: metadata for function.
            _deleteMetadataForFunction(extension.functions[i].functionSelector);
        }

        emit ExtensionRemoved(_extensionName, extension);
    }

    /**
     *  @notice Add a single function to an existing extension.
     */
    function addFunctionToExtension(string memory _extensionName, ExtensionFunction memory _function) external {
        // Check: extension namespace must already exist.
        require(_canAddFunctionToExtension(_extensionName, _function), "ExtensionManager: cannot Store: function for extension.");
        
        // 1. Store: function for extension.
        _addFunctionToExtension(_extensionName, _function);

        ExtensionMetadata memory metadata = _extensionManagerStorage().extensions[_extensionName].metadata;
        // 2. Store: metadata for function.
        _setMetadataForFunction(_function.functionSelector, metadata);

        emit FunctionAdded(_extensionName, _function.functionSelector, _function, metadata);
    }

    /**
     *  @notice Remove a single function from an existing extension.
     */
    function removeFunctionFromExtension(string memory _extensionName, bytes4 _functionSelector) external {
        // Check: extension namespace must already exist.
        // Check: function must be mapped to provided extension.
        require(_canRemoveFunctionFromExtension(_extensionName, _functionSelector), "ExtensionManager: cannot remove function from extension.");
    
        ExtensionMetadata memory extMetadata = _extensionManagerStorage().extensionMetadata[_functionSelector];

        // 1. Delete: function from extension.
        _removeFunctionFromExtension(_extensionName, _functionSelector);
        // 2. Delete: metadata for function.
        _deleteMetadataForFunction(_functionSelector);

        emit FunctionRemoved(_extensionName, _functionSelector, extMetadata);
    }
    
    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the Extension for a given name.
    function _getExtension(string memory _extensionName) internal view returns (Extension memory) {
        return _extensionManagerStorage().extensions[_extensionName];
    }

    /// @dev Sets the ExtensionMetadata for a given extension.
    function _setMetadataForExtension(string memory _extensionName, ExtensionMetadata memory _metadata) internal {
        _extensionManagerStorage().extensions[_extensionName].metadata = _metadata;
    }

    /// @dev Deletes the ExtensionMetadata for a given extension.
    function _deleteMetadataForExtension(string memory _extensionName) internal {
        delete _extensionManagerStorage().extensions[_extensionName].metadata;
    }

    /// @dev Sets the ExtensionMetadata for a given function.
    function _setMetadataForFunction(bytes4 _functionSelector, ExtensionMetadata memory _metadata) internal {
        _extensionManagerStorage().extensionMetadata[_functionSelector] = _metadata;
    }

    /// @dev Deletes the ExtensionMetadata for a given function.
    function _deleteMetadataForFunction(bytes4 _functionSelector) internal {
        delete _extensionManagerStorage().extensionMetadata[_functionSelector];
    }

    /// @dev Adds a given function to an Extension.
    function _addFunctionToExtension(string memory _extensionName, ExtensionFunction memory _extFunction) internal {
        /**
         *  Note: `bytes4(0)` is the function selector for the `receive` function.
         *        So, we maintain a special fn selector-signature mismatch check for the `receive` function.
        **/
        bool mismatch = false;
        if(_extFunction.functionSelector == bytes4(0)) {
            mismatch = keccak256(abi.encode(_extFunction.functionSignature)) != keccak256(abi.encode("receive()"));
        } else {
            mismatch = _extFunction.functionSelector !=
                bytes4(keccak256(abi.encodePacked(_extFunction.functionSignature)));
        }
            
        // Check: function selector and signature must match.
        require(
            !mismatch,
            "ExtensionManager: fn selector and signature mismatch."
        );
        // Check: function must not already be mapped to an implementation.
        require(
            _extensionManagerStorage().extensionMetadata[_extFunction.functionSelector].implementation == address(0),
            "ExtensionManager: function impl already exists."
        );

        // Store: name -> extension.functions map
        _extensionManagerStorage().extensions[_extensionName].functions.push(_extFunction);
    }

    /// @dev Removes a given function from an Extension.
    function _removeFunctionFromExtension(string memory _extensionName, bytes4 _functionSelector) internal {
        ExtensionFunction[] memory extensionFunctions = _extensionManagerStorage().extensions[_extensionName].functions;

        uint256 len = extensionFunctions.length;
        for (uint256 i = 0; i < len; i += 1) {
            if(extensionFunctions[i].functionSelector == _functionSelector) {

                // Delete: particular function from name -> extension.functions map
                _extensionManagerStorage().extensions[_extensionName].functions[i] = _extensionManagerStorage().extensions[_extensionName].functions[len - 1];
                _extensionManagerStorage().extensions[_extensionName].functions.pop();
                break;
            }
        }
    }

    /// @dev Removes all functions from an Extension.
    function _removeAllFunctionsFromExtension(string memory _extensionName) internal {        
        // Delete: existing name -> extension.functions map
        delete _extensionManagerStorage().extensions[_extensionName].functions;
    }

    /// @dev Returns whether a new extension can be added in the given execution context.
    function _canAddExtension(Extension memory _extension) internal virtual returns (bool) {
        // Check: provided extension namespace must not be empty.
        require(bytes(_extension.metadata.name).length > 0, "ExtensionManager: empty name.");
        
        // Check: extension namespace must not already exist.
        // Store: new extension name.
        require(_extensionManagerStorage().extensionNames.add(_extension.metadata.name), "ExtensionManager: extension already exists.");

        // Check: extension implementation must be non-zero.
        require(_extension.metadata.implementation != address(0), "ExtensionManager: adding extension without implementation.");

        return true;
    }

    /// @dev Returns whether an extension can be replaced in the given execution context.
    function _canReplaceExtension(Extension memory _extension) internal view virtual returns (bool) {
        // Check: extension namespace must already exist.
        require(_extensionManagerStorage().extensionNames.contains(_extension.metadata.name), "ExtensionManager: extension does not exist.");

        // Check: extension implementation must be non-zero.
        require(_extension.metadata.implementation != address(0), "ExtensionManager: adding extension without implementation.");

        return true;
    }

    /// @dev Returns whether an extension can be removed in the given execution context.
    function _canRemoveExtension(string memory _extensionName) internal virtual returns (bool) {
        // Check: extension namespace must already exist.
        // Delete: extension namespace.
        require(_extensionManagerStorage().extensionNames.remove(_extensionName), "ExtensionManager: extension does not exist.");

        return true;
    }

    /// @dev Returns whether a function can be added to an extension in the given execution context.
    function _canAddFunctionToExtension(string memory _extensionName, ExtensionFunction memory) internal view virtual returns (bool) {
        // Check: extension namespace must already exist.
        require(_extensionManagerStorage().extensionNames.contains(_extensionName), "ExtensionManager: extension does not exist.");

        return true;
    }

    /// @dev Returns whether an extension can be removed from an extension in the given execution context.
    function _canRemoveFunctionFromExtension(string memory _extensionName, bytes4 _functionSelector) internal view virtual returns (bool) {
        // Check: extension namespace must already exist.
        require(_extensionManagerStorage().extensionNames.contains(_extensionName), "ExtensionManager: extension does not exist.");
        // Check: function must be mapped to provided extension.
        require(keccak256(abi.encode(_extensionManagerStorage().extensionMetadata[_functionSelector].name)) == keccak256(abi.encode(_extensionName)), "ExtensionManager: incorrect extension.");

        return true;
    }

    /// @dev Returns the ExtensionManager storage.
    function _extensionManagerStorage() internal pure returns (ExtensionManagerStorage.Data storage data) {
        data = ExtensionManagerStorage.data();
    }
}