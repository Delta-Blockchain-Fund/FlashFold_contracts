// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

pragma experimental ABIEncoderV2;

import "./aave/FlashLoanReceiverBaseV2.sol";
import "interfaces/v2/ILendingPoolAddressesProviderV2.sol";
import "interfaces/v2/ILendingPoolV2.sol";
import { DataTypes } from "libraries/v2/DataTypes.sol";
import { ILendingPoolV2 } from "interfaces/v2/ILendingPoolV2.sol";

contract AaveFold is FlashLoanReceiverBaseV2 {
    //solhint-disable no-empty-blocks
    // constructor(address _addressProvider) public FlashLoanReceiverBaseV2(_addressProvider) {}

    function foldPosition(
        address asset,
        uint256 inputAmount,
        uint256 foldedDebtAmount,
        address protocolAddress
    ) external nonZero(inputAmount) {
        require(foldedDebtAmount > inputAmount, "E1");

        ILendingPoolV2 LENDING_POOL = getLendingPool(protocolAddress);

        (address[] memory assets, uint256[] memory loanAmount, uint256[] memory modes) = (new address[](1), new uint256[](1), new uint256[](1));
        (assets[0], loanAmount[0], modes[0]) = (asset, foldedDebtAmount.sub(inputAmount), uint256(0));

        bytes memory params = abi.encode(uint8(1), msg.sender, inputAmount, protocolAddress);

        LENDING_POOL.flashLoan(address(this), assets, loanAmount, modes, msg.sender, params, uint16(0));
    }

    function unFoldPosition(address asset, address protocolAddress) external {
        //get debt address
        ILendingPoolV2 LENDING_POOL = getLendingPool(protocolAddress);

        DataTypes.ReserveData memory ReserveData = LENDING_POOL.getReserveData(asset);

        //get total user debt
        uint256 totalDebt = IERC20(ReserveData.variableDebtTokenAddress).balanceOf(msg.sender);

        (address[] memory assets, uint256[] memory loanAmount, uint256[] memory modes) = (new address[](1), new uint256[](1), new uint256[](1));
        (assets[0], loanAmount[0], modes[0]) = (asset, totalDebt, uint256(0));

        bytes memory params = abi.encode(uint8(2), msg.sender, totalDebt, protocolAddress);

        LENDING_POOL.flashLoan(address(this), assets, loanAmount, modes, msg.sender, params, uint16(0));
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes memory params
    ) external override returns (bool) {
        // Received Flash loan

        (uint8 txType, address onBehalfOf, uint256 inputAmount, address protocolAddress) = abi.decode(params, (uint8, address, uint256, address));

        // FOLD
        if (txType == uint8(1)) {
            return _foldInternal(assets[0], inputAmount, onBehalfOf, amounts[0], premiums[0], protocolAddress);
        }
        // UNFOLD
        else if (txType == uint8(2)) {
            return _unfoldInternal(assets[0], inputAmount, onBehalfOf, amounts[0], premiums[0], protocolAddress);
        }
    }

    function _foldInternal(
        address asset,
        uint256 inputAmount,
        address onBehalfOf,
        uint256 flashAmount,
        uint256 premium,
        address protocolAddress
    ) private returns (bool) {
        ILendingPoolV2 LENDING_POOL = getLendingPool(protocolAddress);

        //Receive the input tokens to self Address
        transferTokensToSelf(asset, onBehalfOf, inputAmount);

        uint256 amountOwed = flashAmount.add(premium);

        //AmtToLend = flahLoanAmount + initialInput amount from user
        uint256 lendAmount = flashAmount.add(inputAmount).sub(premium);

        grantAllowance(asset, address(LENDING_POOL), lendAmount);

        LENDING_POOL.deposit(asset, lendAmount, onBehalfOf, uint16(0));

        // Borrow (x+y)*LTV tokens
        uint256 borrowAmount = amountOwed.sub(premium);
        LENDING_POOL.borrow(asset, borrowAmount, uint256(2), uint16(0), onBehalfOf);

        // Pay back flash loan
        // Should have (x+y) collateral, y debt with net interest rate ((x+y)*(deposit rate) - (y)*(borrowing rate))%
        grantAllowance(asset, address(LENDING_POOL), amountOwed);

        //Grant allowance to leanding pool to sweep funds
        return true;
    }

    function _unfoldInternal(
        address asset,
        uint256 debtToRepay,
        address onBehalfOf,
        uint256 flashAmount,
        uint256 premium,
        address protocolAddress
    ) private returns (bool) {
        // Repay debt using flash loan

        ILendingPoolV2 LENDING_POOL = getLendingPool(protocolAddress);

        uint256 amountOwed = flashAmount.add(premium);

        grantAllowance(asset, address(LENDING_POOL), debtToRepay);
        LENDING_POOL.repay(asset, debtToRepay, uint256(2), onBehalfOf);

        DataTypes.ReserveData memory ReserveData = LENDING_POOL.getReserveData(asset);

        uint256 aTokenBalance = IERC20(ReserveData.aTokenAddress).balanceOf(onBehalfOf);

        transferTokensToSelf(ReserveData.aTokenAddress, onBehalfOf, aTokenBalance);

        LENDING_POOL.withdraw(asset, type(uint256).max, address(this));

        uint256 amountOfTokensRecv = IERC20(asset).balanceOf(address(this));

        require(amountOwed <= amountOfTokensRecv, "E2");

        uint256 amountToReturn = amountOfTokensRecv.sub(amountOwed);

        IERC20(asset).transfer(onBehalfOf, amountToReturn);

        grantAllowance(asset, address(LENDING_POOL), amountOwed);

        return true;
    }

    // * ======== HELPER FUNCTIONS ======== * //

    // function getLoanAmount(uint256 input, uint256 LTV) internal pure returns (uint256) {
    //     //input = 100 * inp / 100 - ltv
    //     return ((input.mul(uint256(100))).div(uint256(100).sub(LTV))).sub(input);
    // }

    function getLendingPool(address _address) internal view returns (ILendingPoolV2) {
        return ILendingPoolV2(ILendingPoolAddressesProviderV2(_address).getLendingPool());
    }

    function grantAllowance(
        address asset,
        address spender,
        uint256 amount
    ) internal {
        IERC20(asset).approve(address(spender), amount);
    }

    function transferTokensToSelf(
        address asset,
        address owner,
        uint256 amount
    ) internal {
        IERC20(asset).safeTransferFrom(owner, address(this), amount);
    }

    // * ======== Modifiers ======== * //

    modifier nonZero(uint256 x) {
        require(x > 0, "Amount must be greater than 0");
        _;
    }
}

//E1 - Folded Debt amount must be greater than input amount
//E2 - Not enough balance to repay flashloan
