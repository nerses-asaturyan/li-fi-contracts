// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.17;

import { TestBaseFacet, LibSwap } from "../utils/TestBaseFacet.sol";
import { LayerswapFacet } from "lifi/Facets/LayerswapFacet.sol";
import { ILayerswapDepository } from "lifi/Interfaces/ILayerswapDepository.sol";
import { IERC20 } from "lifi/Libraries/LibAsset.sol";
import { InvalidCallData } from "lifi/Errors/GenericErrors.sol";
import { TestWhitelistManagerBase } from "../utils/TestWhitelistManagerBase.sol";

// Mock depository contract for testing
contract MockLayerswapDepository is ILayerswapDepository {
    bool public shouldRevert;

    error MockRevert();

    event DepositNative(bytes32 indexed id, address indexed receiver, uint256 amount);
    event DepositERC20(
        bytes32 indexed id,
        address indexed token,
        address indexed receiver,
        uint256 amount
    );

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function depositNative(
        bytes32 id,
        address receiver
    ) external payable override {
        if (shouldRevert) {
            revert MockRevert();
        }
        // Forward native tokens to receiver
        (bool success, ) = receiver.call{ value: msg.value }("");
        require(success, "native transfer failed");
        emit DepositNative(id, receiver, msg.value);
    }

    function depositERC20(
        bytes32 id,
        address token,
        address receiver,
        uint256 amount
    ) external override {
        if (shouldRevert) {
            revert MockRevert();
        }
        // Transfer tokens from the caller to receiver
        IERC20(token).transferFrom(msg.sender, receiver, amount);
        emit DepositERC20(id, token, receiver, amount);
    }

    receive() external payable {}
}

// Test LayerswapFacet Contract
contract TestLayerswapFacet is LayerswapFacet, TestWhitelistManagerBase {
    constructor(
        address _layerswapDepository
    ) LayerswapFacet(_layerswapDepository) {}
}

contract LayerswapFacetTest is TestBaseFacet {
    LayerswapFacet.LayerswapData internal validLayerswapData;
    TestLayerswapFacet internal layerswapFacet;
    MockLayerswapDepository internal mockDepository;
    address internal constant LAYERSWAP_RECEIVER =
        0x1234567890123456789012345678901234567890;

    function setUp() public {
        customBlockNumberForForking = 19767662;
        initTestBase();

        // Deploy mock depository
        mockDepository = new MockLayerswapDepository();

        // Deploy facet
        layerswapFacet = new TestLayerswapFacet(address(mockDepository));

        bytes4[] memory functionSelectors = new bytes4[](3);
        functionSelectors[0] = layerswapFacet
            .startBridgeTokensViaLayerswap
            .selector;
        functionSelectors[1] = layerswapFacet
            .swapAndStartBridgeTokensViaLayerswap
            .selector;
        functionSelectors[2] = layerswapFacet
            .addAllowedContractSelector
            .selector;

        addFacet(diamond, address(layerswapFacet), functionSelectors);
        layerswapFacet = TestLayerswapFacet(address(diamond));

        // Setup DEX approvals
        layerswapFacet.addAllowedContractSelector(
            ADDRESS_UNISWAP,
            uniswap.swapExactTokensForTokens.selector
        );
        layerswapFacet.addAllowedContractSelector(
            ADDRESS_UNISWAP,
            uniswap.swapTokensForExactETH.selector
        );
        layerswapFacet.addAllowedContractSelector(
            ADDRESS_UNISWAP,
            uniswap.swapETHForExactTokens.selector
        );

        setFacetAddressInTestBase(
            address(layerswapFacet),
            "LayerswapFacet"
        );

        // Setup bridge data
        bridgeData.bridge = "layerswap";
        bridgeData.destinationChainId = 137;

        // Setup valid layerswap data
        validLayerswapData = LayerswapFacet.LayerswapData({
            orderId: bytes32("test-order-id"),
            receiver: LAYERSWAP_RECEIVER
        });
    }

    function initiateBridgeTxWithFacet(bool isNative) internal override {
        if (isNative) {
            layerswapFacet.startBridgeTokensViaLayerswap{
                value: bridgeData.minAmount
            }(bridgeData, validLayerswapData);
        } else {
            layerswapFacet.startBridgeTokensViaLayerswap(
                bridgeData,
                validLayerswapData
            );
        }
    }

    function initiateSwapAndBridgeTxWithFacet(
        bool isNative
    ) internal override {
        if (isNative) {
            layerswapFacet.swapAndStartBridgeTokensViaLayerswap{
                value: swapData[0].fromAmount
            }(bridgeData, swapData, validLayerswapData);
        } else {
            layerswapFacet.swapAndStartBridgeTokensViaLayerswap(
                bridgeData,
                swapData,
                validLayerswapData
            );
        }
    }

    // Test successful deployment
    function test_CanDeployFacet() public {
        new LayerswapFacet(address(mockDepository));
    }

    // Test revert when constructed with zero address
    function testRevert_WhenConstructedWithZeroAddress() public {
        vm.expectRevert(InvalidCallData.selector);
        new LayerswapFacet(address(0));
    }

    // Test ERC20 deposit
    function test_CanDepositERC20Tokens()
        public
        assertBalanceChange(
            ADDRESS_USDC,
            USER_SENDER,
            -int256(defaultUSDCAmount)
        )
        assertBalanceChange(
            ADDRESS_USDC,
            LAYERSWAP_RECEIVER,
            int256(defaultUSDCAmount)
        )
    {
        vm.startPrank(USER_SENDER);

        // Approval
        usdc.approve(_facetTestContractAddress, bridgeData.minAmount);

        // Expect events
        vm.expectEmit(true, true, true, true, _facetTestContractAddress);
        emit LiFiTransferStarted(bridgeData);

        initiateBridgeTxWithFacet(false);
        vm.stopPrank();
    }

    // Test native token deposit
    function test_CanDepositNativeTokens()
        public
        assertBalanceChange(
            address(0),
            USER_SENDER,
            -int256(defaultNativeAmount + addToMessageValue)
        )
        assertBalanceChange(
            address(0),
            LAYERSWAP_RECEIVER,
            int256(defaultNativeAmount)
        )
    {
        vm.startPrank(USER_SENDER);

        // Customize bridge data for native tokens
        bridgeData.sendingAssetId = address(0);
        bridgeData.minAmount = defaultNativeAmount;

        // Expect events
        vm.expectEmit(true, true, true, true, _facetTestContractAddress);
        emit LiFiTransferStarted(bridgeData);

        initiateBridgeTxWithFacet(true);
        vm.stopPrank();
    }

    // Test swap and deposit ERC20
    function test_CanSwapAndDepositERC20Tokens()
        public
        assertBalanceChange(
            ADDRESS_DAI,
            USER_SENDER,
            -int256(swapData[0].fromAmount)
        )
        assertBalanceChange(
            ADDRESS_USDC,
            LAYERSWAP_RECEIVER,
            int256(bridgeData.minAmount)
        )
    {
        vm.startPrank(USER_SENDER);

        // Prepare bridge data
        bridgeData.hasSourceSwaps = true;

        // Reset swap data
        setDefaultSwapDataSingleDAItoUSDC();

        // Approval
        dai.approve(_facetTestContractAddress, swapData[0].fromAmount);

        // Expect events
        vm.expectEmit(true, true, true, true, _facetTestContractAddress);
        emit AssetSwapped(
            bridgeData.transactionId,
            ADDRESS_UNISWAP,
            ADDRESS_DAI,
            ADDRESS_USDC,
            swapData[0].fromAmount,
            bridgeData.minAmount,
            block.timestamp
        );

        vm.expectEmit(true, true, true, true, _facetTestContractAddress);
        emit LiFiTransferStarted(bridgeData);

        initiateSwapAndBridgeTxWithFacet(false);
        vm.stopPrank();
    }

    // Test swap and deposit native tokens
    function test_CanSwapAndDepositNativeTokens()
        public
        assertBalanceChange(ADDRESS_DAI, USER_RECEIVER, 0)
        assertBalanceChange(ADDRESS_USDC, USER_RECEIVER, 0)
    {
        vm.startPrank(USER_SENDER);

        // Store initial balances
        uint256 initialUsdcBalance = usdc.balanceOf(USER_SENDER);

        // Prepare bridge data
        bridgeData.hasSourceSwaps = true;
        bridgeData.sendingAssetId = address(0);

        // Prepare swap data
        address[] memory path = new address[](2);
        path[0] = ADDRESS_USDC;
        path[1] = ADDRESS_WRAPPED_NATIVE;

        uint256 amountOut = defaultNativeAmount;

        // Calculate USDC input amount
        uint256[] memory amounts = uniswap.getAmountsIn(amountOut, path);
        uint256 amountIn = amounts[0];

        bridgeData.minAmount = amountOut;

        delete swapData;
        swapData.push(
            LibSwap.SwapData({
                callTo: address(uniswap),
                approveTo: address(uniswap),
                sendingAssetId: ADDRESS_USDC,
                receivingAssetId: address(0),
                fromAmount: amountIn,
                callData: abi.encodeWithSelector(
                    uniswap.swapTokensForExactETH.selector,
                    amountOut,
                    amountIn,
                    path,
                    _facetTestContractAddress,
                    block.timestamp + 20 minutes
                ),
                requiresDeposit: true
            })
        );

        // Approval
        usdc.approve(_facetTestContractAddress, amountIn);

        // Expect events
        vm.expectEmit(true, true, true, true, _facetTestContractAddress);
        emit AssetSwapped(
            bridgeData.transactionId,
            ADDRESS_UNISWAP,
            ADDRESS_USDC,
            address(0),
            swapData[0].fromAmount,
            bridgeData.minAmount,
            block.timestamp
        );

        vm.expectEmit(false, false, false, false, _facetTestContractAddress);
        emit LiFiTransferStarted(bridgeData);

        initiateSwapAndBridgeTxWithFacet(false);

        // Check balances
        assertEq(
            usdc.balanceOf(USER_SENDER),
            initialUsdcBalance - swapData[0].fromAmount
        );
        vm.stopPrank();
    }

    // Test revert when native deposit fails
    function testRevert_WhenNativeDepositFails() public {
        // Make the mock depository revert
        mockDepository.setShouldRevert(true);

        vm.startPrank(USER_SENDER);

        // Customize bridge data for native tokens
        bridgeData.sendingAssetId = address(0);
        bridgeData.minAmount = defaultNativeAmount;

        vm.expectRevert();
        initiateBridgeTxWithFacet(true);

        vm.stopPrank();
    }

    // Test revert when ERC20 deposit fails
    function testRevert_WhenERC20DepositFails() public {
        // Make the mock depository revert
        mockDepository.setShouldRevert(true);

        vm.startPrank(USER_SENDER);

        // Approval
        usdc.approve(_facetTestContractAddress, bridgeData.minAmount);

        vm.expectRevert();
        initiateBridgeTxWithFacet(false);

        vm.stopPrank();
    }

    // Test revert when receiver address is zero address
    function testRevert_WhenReceiverAddressIsZero() public {
        vm.startPrank(USER_SENDER);

        // Create invalid layerswap data with zero receiver
        LayerswapFacet.LayerswapData
            memory invalidLayerswapData = LayerswapFacet.LayerswapData({
                orderId: bytes32("test-order-id"),
                receiver: address(0)
            });

        // Approval for ERC20 case
        usdc.approve(_facetTestContractAddress, bridgeData.minAmount);

        // Expect revert with InvalidCallData error for ERC20 deposit
        vm.expectRevert(InvalidCallData.selector);
        layerswapFacet.startBridgeTokensViaLayerswap(
            bridgeData,
            invalidLayerswapData
        );

        // Test native token case as well
        bridgeData.sendingAssetId = address(0);
        bridgeData.minAmount = defaultNativeAmount;

        // Expect revert with InvalidCallData error for native deposit
        vm.expectRevert(InvalidCallData.selector);
        layerswapFacet.startBridgeTokensViaLayerswap{
            value: defaultNativeAmount
        }(bridgeData, invalidLayerswapData);

        vm.stopPrank();
    }

    // Test revert when receiver is zero in swap and bridge
    function testRevert_WhenReceiverIsZeroInSwapAndBridge() public {
        vm.startPrank(USER_SENDER);

        // Create invalid layerswap data with zero receiver
        LayerswapFacet.LayerswapData
            memory invalidLayerswapData = LayerswapFacet.LayerswapData({
                orderId: bytes32("test-order-id"),
                receiver: address(0)
            });

        // Prepare bridge data with source swaps
        bridgeData.hasSourceSwaps = true;

        // Reset swap data
        setDefaultSwapDataSingleDAItoUSDC();

        // Approval
        dai.approve(_facetTestContractAddress, swapData[0].fromAmount);

        // Expect revert with InvalidCallData error
        vm.expectRevert(InvalidCallData.selector);
        layerswapFacet.swapAndStartBridgeTokensViaLayerswap(
            bridgeData,
            swapData,
            invalidLayerswapData
        );

        vm.stopPrank();
    }

    // Test fuzzed amounts
    function test_FuzzedAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100_000);
        amount = amount * 10 ** usdc.decimals();

        vm.startPrank(USER_SENDER);

        // Set unique order ID for each fuzz run
        validLayerswapData.orderId = keccak256(
            abi.encodePacked("fuzz", amount)
        );

        // Approval
        usdc.approve(_facetTestContractAddress, amount);

        // Update bridge data
        bridgeData.sendingAssetId = ADDRESS_USDC;
        bridgeData.minAmount = amount;

        // Execute and verify
        uint256 initialBalance = usdc.balanceOf(LAYERSWAP_RECEIVER);
        initiateBridgeTxWithFacet(false);
        assertEq(
            usdc.balanceOf(LAYERSWAP_RECEIVER),
            initialBalance + amount
        );

        vm.stopPrank();
    }
}
