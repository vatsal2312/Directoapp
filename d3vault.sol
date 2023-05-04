// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Address.sol";

/**
@title asset holder contract by d3Launch 
@author https://gitlab.com/directo3Inc
@notice This Contract is part of directo3Inc Ecosystem
*/
contract D3VAULT is ReentrancyGuard, Ownable {
    event Claimed(uint256 amount); // event to emit when a claim is made
    event Claimed(address token, uint256 amount); // event to emit when a claim is made

    struct Payee {
        uint256 Share;
        address Address;
    }

    Payee[] public payeeList;

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    //==================  Administrative Functions    ==================//

    function setupPayees(
        address[] calldata _addresses,
        uint256[] calldata _shares
    ) external nonReentrant onlyOwner {
        require(_addresses.length == _shares.length, "Arrays length not equal");

        uint256 totalShares;
        for (uint256 i = 0; i < _shares.length; ++i) {
            totalShares += _shares[i];
        }
        require(totalShares == 100, "Total Shares should be 100");

        for (uint256 i = 0; i < payeeList.length; ++i) {
            payeeList.pop();
        }

        for (uint256 i = 0; i < _addresses.length; ++i) {
            payeeList.push(Payee(_shares[i], _addresses[i]));
        }
    }

    //==================  Public Functions    ==================//

    function claim() external payable nonReentrant {
        uint256 currentBalance = address(this).balance;

        for (uint256 i = 0; i < payeeList.length; i++) {
            Address.sendValue(
                payable(payeeList[i].Address),
                (currentBalance * payeeList[i].Share) / 100
            );
        }
        emit Claimed(currentBalance);
    }

    function claim(address _token) external payable nonReentrant {
        IERC20 token = IERC20(_token);
        uint256 currentBalance = token.balanceOf(address(this));

        for (uint256 i = 0; i < payeeList.length; i++) {
            token.transfer(
                payeeList[i].Address,
                (currentBalance * payeeList[i].Share) / 100
            );
        }
        emit Claimed(_token, currentBalance);
    }

    //==================  Read only Functions    ==================//

    function contractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function contractBalance(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function totalPayees() public view returns (uint256) {
        return payeeList.length;
    }
}
