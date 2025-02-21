// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { NexusTest_Base } from "../../../utils/NexusTest_Base.t.sol";
import "../../../utils/Imports.sol";
import { MockTarget } from "contracts/mocks/MockTarget.sol";
import { IExecutionHelper } from "contracts/interfaces/base/IExecutionHelper.sol";
import { IHook } from "contracts/interfaces/modules/IHook.sol";
import { IPreValidationHookERC1271, IPreValidationHookERC4337 } from "contracts/interfaces/modules/IPreValidationHook.sol";
import { MockPreValidationHook } from "contracts/mocks/MockPreValidationHook.sol";

contract TestEIP7702 is NexusTest_Base {
    using ECDSA for bytes32;

    MockDelegateTarget delegateTarget;
    MockTarget target;
    MockValidator public mockValidator;
    MockExecutor public mockExecutor;

    function setUp() public {
        setupTestEnvironment();
        delegateTarget = new MockDelegateTarget();
        target = new MockTarget();
        mockValidator = new MockValidator();
        mockExecutor = new MockExecutor();
    }

    function _doEIP7702(address account) internal {
        //vm.etch(account, address(ACCOUNT_IMPLEMENTATION).code);
        vm.etch(account, abi.encodePacked(bytes3(0xef0100), bytes20(address(ACCOUNT_IMPLEMENTATION))));
    }

    function _getInitData() internal view returns (bytes memory) {
        // Create config for initial modules
        BootstrapConfig[] memory validators = BootstrapLib.createArrayConfig(address(mockValidator), "");
        BootstrapConfig[] memory executors = BootstrapLib.createArrayConfig(address(mockExecutor), "");
        BootstrapConfig memory hook = BootstrapLib.createSingleConfig(address(0), "");
        BootstrapConfig[] memory fallbacks = BootstrapLib.createArrayConfig(address(0), "");

        return BOOTSTRAPPER.getInitNexusCalldata(validators, executors, hook, fallbacks, REGISTRY, ATTESTERS, THRESHOLD);
    }

    function _getSignature(uint256 eoaKey, PackedUserOperation memory userOp) internal view returns (bytes memory) {
        bytes32 hash = ENTRYPOINT.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaKey, hash.toEthSignedMessageHash());
        return abi.encodePacked(r, s, v);
    }

    function test_execSingle() public returns (address) {
        // Create calldata for the account to execute
        bytes memory setValueOnTarget = abi.encodeCall(MockTarget.setValue, 1337);

        // Encode the call into the calldata for the userOp
        bytes memory userOpCalldata =
            abi.encodeCall(IExecutionHelper.execute, (ModeLib.encodeSimpleSingle(), ExecLib.encodeSingle(address(target), uint256(0), setValueOnTarget)));

        // Get the account, initcode and nonce
        uint256 eoaKey = uint256(8);
        address account = vm.addr(eoaKey);
        vm.deal(account, 100 ether);

        uint256 nonce = getNonce(account, MODE_VALIDATION, address(mockValidator), 0);

        // Create the userOp and add the data
        PackedUserOperation memory userOp = buildPackedUserOp(address(account), nonce);
        userOp.callData = userOpCalldata;
        userOp.callData = userOpCalldata;

        userOp.signature = _getSignature(eoaKey, userOp);
        _doEIP7702(account);

        // Create userOps array
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // Send the userOp to the entrypoint
        ENTRYPOINT.handleOps(userOps, payable(address(0x69)));

        // Assert that the value was set ie that execution was successful
        assertTrue(target.value() == 1337);
        return account;
    }

    function test_initializeAndExecSingle() public returns (address) {
        // Get the account, initcode and nonce
        uint256 eoaKey = uint256(8);
        address account = vm.addr(eoaKey);
        vm.deal(account, 100 ether);

        // Create calldata for the account to execute
        bytes memory setValueOnTarget = abi.encodeCall(MockTarget.setValue, 1337);

        bytes memory initData = _getInitData();

        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({ target: account, value: 0, callData: abi.encodeCall(INexus.initializeAccount, initData) });
        executions[1] = Execution({ target: address(target), value: 0, callData: setValueOnTarget });

        // Encode the call into the calldata for the userOp
        bytes memory userOpCalldata = abi.encodeCall(IExecutionHelper.execute, (ModeLib.encodeSimpleBatch(), ExecLib.encodeBatch(executions)));

        uint256 nonce = getNonce(account, MODE_VALIDATION, address(mockValidator), 0);

        // Create the userOp and add the data
        PackedUserOperation memory userOp = buildPackedUserOp(address(account), nonce);
        userOp.callData = userOpCalldata;

        userOp.signature = _getSignature(eoaKey, userOp);
        _doEIP7702(account);

        // Create userOps array
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // Send the userOp to the entrypoint
        ENTRYPOINT.handleOps(userOps, payable(address(0x69)));

        // Assert that the value was set ie that execution was successful
        assertTrue(target.value() == 1337);
        return account;
    }

    function test_execBatch() public {
        // Create calldata for the account to execute
        bytes memory setValueOnTarget = abi.encodeCall(MockTarget.setValue, 1337);
        address target2 = address(0x420);
        uint256 target2Amount = 1 wei;

        // Create the executions
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({ target: address(target), value: 0, callData: setValueOnTarget });
        executions[1] = Execution({ target: target2, value: target2Amount, callData: "" });

        // Encode the call into the calldata for the userOp
        bytes memory userOpCalldata = abi.encodeCall(IExecutionHelper.execute, (ModeLib.encodeSimpleBatch(), ExecLib.encodeBatch(executions)));

        // Get the account, initcode and nonce
        uint256 eoaKey = uint256(8);
        address account = vm.addr(eoaKey);
        vm.deal(account, 100 ether);

        uint256 nonce = getNonce(account, MODE_VALIDATION, address(mockValidator), 0);

        // Create the userOp and add the data
        PackedUserOperation memory userOp = buildPackedUserOp(address(account), nonce);
        userOp.callData = userOpCalldata;
        userOp.callData = userOpCalldata;

        userOp.signature = _getSignature(eoaKey, userOp);
        _doEIP7702(account);

        // Create userOps array
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // Send the userOp to the entrypoint
        ENTRYPOINT.handleOps(userOps, payable(address(0x69)));

        // Assert that the value was set ie that execution was successful
        assertTrue(target.value() == 1337);
        assertTrue(target2.balance == target2Amount);
    }

    function test_execSingleFromExecutor() public {
        address account = test_initializeAndExecSingle();

        bytes[] memory ret =
            mockExecutor.executeViaAccount(INexus(address(account)), address(target), 0, abi.encodePacked(MockTarget.setValue.selector, uint256(1338)));

        assertEq(ret.length, 1);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_execBatchFromExecutor() public {
        address account = test_initializeAndExecSingle();

        bytes memory setValueOnTarget = abi.encodeCall(MockTarget.setValue, 1338);
        Execution[] memory executions = new Execution[](2);
        executions[0] = Execution({ target: address(target), value: 0, callData: setValueOnTarget });
        executions[1] = Execution({ target: address(target), value: 0, callData: setValueOnTarget });
        bytes[] memory ret = mockExecutor.executeBatchViaAccount({ account: INexus(address(account)), execs: executions });

        assertEq(ret.length, 2);
        assertEq(abi.decode(ret[0], (uint256)), 1338);
    }

    function test_delegateCall() public {
        // Create calldata for the account to execute
        address valueTarget = makeAddr("valueTarget");
        uint256 value = 1 ether;
        bytes memory sendValue = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, valueTarget, value);

        // Encode the call into the calldata for the userOp
        bytes memory userOpCalldata = abi.encodeCall(
            IExecutionHelper.execute,
            (
                ModeLib.encode(CALLTYPE_DELEGATECALL, EXECTYPE_DEFAULT, MODE_DEFAULT, ModePayload.wrap(0x00)),
                abi.encodePacked(address(delegateTarget), sendValue)
            )
        );

        // Get the account, initcode and nonce
        uint256 eoaKey = uint256(8);
        address account = vm.addr(eoaKey);
        vm.deal(account, 100 ether);

        uint256 nonce = getNonce(account, MODE_VALIDATION, address(mockValidator), 0);

        // Create the userOp and add the data
        PackedUserOperation memory userOp = buildPackedUserOp(address(account), nonce);
        userOp.callData = userOpCalldata;
        userOp.callData = userOpCalldata;

        userOp.signature = _getSignature(eoaKey, userOp);
        _doEIP7702(account);

        // Create userOps array
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        // Send the userOp to the entrypoint
        ENTRYPOINT.handleOps(userOps, payable(address(0x69)));

        // Assert that the value was set ie that execution was successful
        assertTrue(valueTarget.balance == value);
    }

    function test_delegateCall_fromExecutor() public {
        address account = test_initializeAndExecSingle();

        // Create calldata for the account to execute
        address valueTarget = makeAddr("valueTarget");
        uint256 value = 1 ether;
        bytes memory sendValue = abi.encodeWithSelector(MockDelegateTarget.sendValue.selector, valueTarget, value);

        // Execute the delegatecall via the executor
        mockExecutor.execDelegatecall(INexus(address(account)), abi.encodePacked(address(delegateTarget), sendValue));

        // Assert that the value was set ie that execution was successful
        assertTrue(valueTarget.balance == value);
    }

    function test_erc7702_redelegate() public {
        address account = test_initializeAndExecSingle();

        MockPreValidationHook preValidationHook = new MockPreValidationHook();

        vm.startPrank(address(account));
        INexus(account).installModule(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271, address(preValidationHook), "");
        INexus(account).installModule(MODULE_TYPE_PREVALIDATION_HOOK_ERC4337, address(preValidationHook), "");
        vm.stopPrank();

        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(mockValidator), ""));
        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(mockExecutor), ""));
        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271, address(preValidationHook), ""));
        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_PREVALIDATION_HOOK_ERC4337, address(preValidationHook), ""));

        bytes memory initData = abi.encode(
            address(BOOTSTRAPPER),
            abi.encodeWithSelector(
                NexusBootstrap.initNexusWithSingleValidator.selector, 
                mockValidator, 
                abi.encodePacked(address(0xa11ce)), 
                IERC7484(address(0)),
                new address[](0),
                0
            )
        );

        // simulate redelegation flow
        vm.prank(address(account));
        INexus(account).onRedelegation(); // storage is cleared

        assertFalse(INexus(account).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(mockValidator), ""));
        assertFalse(INexus(account).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(mockExecutor), ""));
        assertFalse(INexus(account).isModuleInstalled(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271, address(preValidationHook), ""));
        assertFalse(INexus(account).isModuleInstalled(MODULE_TYPE_PREVALIDATION_HOOK_ERC4337, address(preValidationHook), ""));
        
        vm.prank(address(account)); 
        INexus(account).initializeAccount(initData); // account is reinitialized for the new delegate (sa implementation)
        
        // account is properly initialized to install modules again
        vm.startPrank(address(ENTRYPOINT));
        // INexus(account).installModule(MODULE_TYPE_VALIDATOR, address(mockValidator), ""); ==> already installed at initialization
        INexus(account).installModule(MODULE_TYPE_EXECUTOR, address(mockExecutor), "");
        INexus(account).installModule(MODULE_TYPE_HOOK, address(HOOK_MODULE), "");
        INexus(account).installModule(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271, address(preValidationHook), "");
        INexus(account).installModule(MODULE_TYPE_PREVALIDATION_HOOK_ERC4337, address(preValidationHook), "");
        vm.stopPrank();

        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_VALIDATOR, address(mockValidator), ""));
        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_EXECUTOR, address(mockExecutor), ""));
        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_HOOK, address(HOOK_MODULE), ""));
        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_PREVALIDATION_HOOK_ERC1271, address(preValidationHook), ""));
        assertTrue(INexus(account).isModuleInstalled(MODULE_TYPE_PREVALIDATION_HOOK_ERC4337, address(preValidationHook), ""));
    }

    // TODO:  make proper tests when Foundry supports 7702 and etching of 0xef0100xxxx
    function test_amIERC7702_success()public {
        ExposedNexus exposedNexus = new ExposedNexus(address(ENTRYPOINT));
        address eip7702account = address(0x7702acc7702acc7702acc7702acc);
        // vm.etch(eip7702account, abi.encodePacked(bytes3(0xef0100), bytes20(address(exposedNexus))));
        // assertTrue(IExposedNexus(eip7702account).amIERC7702()); // it doesnt work yet as forge tests can not do proper 7702 atm
        
        // can not even etch 0xef0100 as forge considers 00 as end of code and stops etching
        // using 111111 as a temporary workaround
        vm.etch(eip7702account, hex'11111196d3f6c20eed2697647f543fe6c08bc2fbf39758');
        //console2.logBytes(eip7702account.code);
        
        (bool res, bool res2) = _isERC7702(eip7702account);
        assertTrue(res);
        assertTrue(res2);    
    }

    // HELPER FUNCTION UNTIL FULL 7702 SUPPORT IN TESTS
    function _isERC7702(address account) internal view returns (bool res, bool res2) {
        uint256 codeSize;
        bytes32 code;
        assembly {
            // use extcodesize as the first cheapest check
            codeSize := extcodesize(account)
            if eq(codeSize, 23) {
                // use extcodecopy to copy first 3 bytes of this contract and compare with 0xef0100 // 0x111111
                let ptr := mload(0x40)
                extcodecopy(account, ptr, 0, 3)
                code := and(mload(ptr), 0xffffff0000000000000000000000000000000000000000000000000000000000)
                //if eq(mload(ptr), 0xef0100) {
                if eq(
                        code, 
                        0x1111110000000000000000000000000000000000000000000000000000000000
                    ) {
                        res := true
                }
                
            }
            // if it is not 23, we do not even check the code
        }
        res2 = bytes3(code) == bytes3(0x111111);
        //console2.log("codeSize", codeSize);
        //console2.logBytes32(code);
        return (res, res2);
    }
}